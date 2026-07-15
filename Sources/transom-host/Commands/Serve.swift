import ApplicationServices
import ArgumentParser
import CoreGraphics
import CoreMedia
import Foundation
import TransomKit

/// `serve <app> <display>` — Phase 3 of issue #3: the wire.
///
/// Tiles the app's windows, watches them via AX, and serves the control channel
/// (window lifecycle + geometry, in VDS physical pixels) to a client that
/// connects by IP. With `--video`, it also captures + HEVC-encodes the display
/// and streams it on a second connection.
///
/// There is **no auth and no encryption** (see the README security note), so the
/// host refuses to bind to anything but a private address.
struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Tile + watch an app and serve its window rects (and optionally video) over TCP.")

    @Argument(help: "Target app: a name like \"Xcode\" or a bundle id.")
    var app: String

    @Argument(help: "Display id, as printed by `displays`.")
    var display: UInt32

    @Option(
        name: .long,
        help: "Private address to bind (default localhost). Use the LAN IP for a real client.")
    var host: String = "127.0.0.1"

    @Option(name: .long, help: "Control channel TCP port.")
    var controlPort: UInt16 = 7000

    @Option(name: .long, help: "Video channel TCP port.")
    var videoPort: UInt16 = 7001

    @Option(name: .long, help: "Gutter in VDS pixels between tiles.")
    var gutter: Int = Tiler.defaultGutter

    @Flag(inversion: .prefixedNo, help: "Tile the app's windows at startup (I-5).")
    var tile: Bool = true

    @Flag(name: .long, help: "Also capture + HEVC-encode and stream video on the 2nd connection.")
    var video: Bool = false

    @Option(name: .long, help: "Video target bitrate in Mbps.")
    var bitrate: Int = 40

    @Option(name: .long, help: "Video target frame rate.")
    var fps: Int = 60

    @Option(name: .long, help: "Auto-stop after N seconds (default: run until Ctrl-C).")
    var seconds: Double?

    func run() async throws {
        // Stream output live: stdout is block-buffered to a pipe/file, so without
        // this the status lines never appear while the long-running server runs.
        setvbuf(stdout, nil, _IONBF, 0)

        guard AXIsProcessTrusted() else {
            throw ProbeError(
                "Accessibility is not granted. Run `transom-host doctor` for guidance.")
        }
        if video && !CGPreflightScreenCaptureAccess() {
            throw ProbeError("Screen Recording is not granted, required for --video. See `doctor`.")
        }
        guard PrivateAddress.isPrivateIPv4(host) else {
            throw ProbeError(TransportError.refusedPublicBind(host).description)
        }

        let target: TargetApp
        switch AppResolver.resolve(app) {
        case .success(let t): target = t
        case .failure(let e): throw e
        }
        guard let disp = TransomKit.Displays.byID(display) else {
            throw ProbeError("no active display with id \(display). See `displays`.")
        }

        print(
            "serve: \(target.name) on display \(display) (\(disp.pixelWidth)x\(disp.pixelHeight) px)"
        )
        print(
            "  control: \(host):\(controlPort)   video: \(video ? "\(host):\(videoPort)" : "off")")

        if tile {
            switch TileService.tile(pid: target.pid, display: disp, gutter: gutter) {
            case .success(let n): print("  tiled \(n) window(s), gutter=\(gutter)px")
            case .failure(let e): print("  tiling skipped: \(e)")
            }
        }

        let registry = WindowRegistry()
        let vdsSize = WireSize(w: UInt32(disp.pixelWidth), h: UInt32(disp.pixelHeight))

        // Control channel: events -> broadcast in order via one AsyncStream.
        let (events, eventSink) = AsyncStream.makeStream(of: WindowWatcher.WindowEvent.self)
        let watcher = WindowWatcher(pid: target.pid, display: disp, registry: registry)
        watcher.onEvent = { event in eventSink.yield(event) }

        // Phase 4 (issue #6): the geometry roundtrip. Client RequestResize is
        // throttled (~10Hz), written to AX, read back, and emitted as windowMoved
        // (ACTUAL geometry, I-4) through the same ordered event stream. Requests
        // are handled in arrival order via their own stream so AX writes serialise.
        let resize = ResizeService(
            registry: registry, display: disp, gutter: gutter,
            emit: { event in eventSink.yield(event) })
        let (clientMessages, clientSink) = AsyncStream.makeStream(of: ClientMessage.self)

        let controlServer = ControlServer(vdsSize: vdsSize, registry: registry)
        await controlServer.setOnClientMessage { message in clientSink.yield(message) }
        let controlListener = try TCPListener(host: host, port: controlPort, label: "control")

        // Start the AX watcher on its own run-loop thread and wait until it has
        // registered + seeded the registry, so a client that connects immediately
        // gets a complete resync. The continuation resumes after start() but before
        // CFRunLoopRun() takes over the thread.
        let ctx = WatcherThread()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let watcherThread = Thread {
                ctx.runLoop = CFRunLoopGetCurrent()
                do {
                    try watcher.start()
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
                CFRunLoopRun()
            }
            watcherThread.stackSize = 1 << 20
            watcherThread.start()
        }

        let controlTask = Task { await controlServer.serve(listener: controlListener) }
        let forwardTask = Task {
            for await event in events { await controlServer.broadcast(event) }
        }
        // Drive resize requests in arrival order (AX writes serialise on the actor),
        // and tick at ~20Hz so a coalesced live from a paused drag still flushes.
        let resizeTask = Task {
            for await message in clientMessages {
                if case let .requestResize(id, size, phase) = message {
                    await resize.handle(id: id, size: size, phase: phase)
                } else {
                    Log.general.notice(
                        "control: client -> \(String(describing: message), privacy: .public)")
                }
            }
        }
        let tickTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                await resize.tick()
            }
        }
        controlListener.start()

        // Optional video channel.
        var videoListener: TCPListener?
        var capture: DisplayCapture?
        var encoder: HEVCEncoder?
        var videoTask: Task<Void, Never>?
        var frameTask: Task<Void, Never>?
        if video {
            let enc = try HEVCEncoder(
                config: HEVCEncoder.Config(
                    width: disp.pixelWidth, height: disp.pixelHeight, fps: fps,
                    bitrateBitsPerSecond: bitrate * 1_000_000, maxKeyFrameInterval: fps * 2))
            enc.extractFrameData = true
            let videoServer = VideoServer(hvccProvider: { enc.parameterSetsHVCC })
            let listener = try TCPListener(host: host, port: videoPort, label: "video")

            let (frames, frameSink) = AsyncStream.makeStream(
                of: HEVCEncoder.EncodedFrame.self, bufferingPolicy: .bufferingNewest(4))
            enc.onEncodedFrame = { frame in frameSink.yield(frame) }

            let cap = DisplayCapture(display: disp, fps: fps)
            let frameDuration = CMTimeMake(value: 1, timescale: Int32(fps))
            cap.onPixelBuffer = { pixelBuffer, pts in
                try? enc.encode(pixelBuffer, pts: pts, duration: frameDuration)
            }
            try await cap.start()

            videoTask = Task { await videoServer.serve(listener: listener) }
            frameTask = Task { for await f in frames { await videoServer.send(f) } }
            listener.start()
            print("  video: hardware=\(enc.usingHardware), streaming HEVC 4:4:4 10-bit")

            videoListener = listener
            capture = cap
            encoder = enc
        }

        print(
            "  ready. waiting for a client to connect\(seconds.map { " (auto-stop in \($0)s)" } ?? " (Ctrl-C to stop)")."
        )

        if let seconds {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        } else {
            // Run until the process is interrupted.
            while true { try await Task.sleep(nanoseconds: 60 * 1_000_000_000) }
        }

        // Clean shutdown (only reached in --seconds mode).
        let (reqIn, writes) = (await resize.requestsIn, await resize.axWrites)
        if reqIn > 0 {
            print(
                "  resize: \(reqIn) request(s) in, \(writes) AX write(s) out (throttled to ~10Hz)")
        }
        controlListener.stop()
        videoListener?.stop()
        if let capture { await capture.stop() }
        encoder?.finish()
        eventSink.finish()
        clientSink.finish()
        controlTask.cancel()
        forwardTask.cancel()
        resizeTask.cancel()
        tickTask.cancel()
        videoTask?.cancel()
        frameTask?.cancel()
        if let runLoop = ctx.runLoop { CFRunLoopStop(runLoop) }
        print("serve: stopped.")
    }
}

/// Cross-thread handoff for the watcher run-loop thread: its `CFRunLoop`, so the
/// command can stop it on shutdown. The continuation in `run()` orders the write
/// (on the thread) before any read (on the caller).
private final class WatcherThread: @unchecked Sendable {
    var runLoop: CFRunLoop?
}
