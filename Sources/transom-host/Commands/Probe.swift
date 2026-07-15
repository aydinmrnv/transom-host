import ApplicationServices
import ArgumentParser
import CoreGraphics
import Foundation
import TransomKit

/// `probe <app> <display> --out <dir>` — the alignment + lag instrument (OQ-5).
///
/// Runs an SCK stream of the display and polls the app's AX window rects at
/// ~10Hz. Each tick it dumps a PNG of the frame with the AX rects drawn on top
/// as colored outlines (labelled role/subrole), and appends a JSONL record of
/// every window rect with a timestamp.
///
/// Comparing the drawn rect against the pixels underneath answers whether AX
/// rects align pixel-exactly with SCK pixels; comparing rect motion across
/// frames against the pixels answers by how many frames the metadata lags.
struct Probe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "probe",
        abstract: "SCK + AX rects at ~10Hz: dump overlaid frames and a JSONL rect log.")

    @Argument(help: "Target app: a name like \"Xcode\" or a bundle id.")
    var app: String

    @Argument(help: "Display id, as printed by `displays`.")
    var display: UInt32

    @Option(name: .long, help: "Output directory for frames and the JSONL log.")
    var out: String

    @Option(name: .long, help: "Capture frame rate.")
    var fps: Int = 60

    @Option(name: .long, help: "AX polling rate (Hz).")
    var hz: Int = 10

    @Option(name: .long, help: "How long to run, in seconds.")
    var duration: Double = 5

    func run() async throws {
        setvbuf(stdout, nil, _IONBF, 0)
        guard CGPreflightScreenCaptureAccess() else {
            throw ProbeError("Screen Recording is not granted. See `transom-host doctor`.")
        }
        guard AXIsProcessTrusted() else {
            throw ProbeError("Accessibility is not granted. See `transom-host doctor`.")
        }

        let target: TargetApp
        switch AppResolver.resolve(app) {
        case .success(let t): target = t
        case .failure(let e): throw e
        }
        guard let disp = TransomKit.Displays.byID(display) else {
            throw ProbeError("no active display with id \(display). See `displays`.")
        }

        let outDir = URL(fileURLWithPath: out, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outDir, withIntermediateDirectories: true)

        print("probe: \(target.name) on display \(display) (\(disp.pixelWidth)x\(disp.pixelHeight) px)")
        print("  out=\(outDir.path)  fps=\(fps)  poll=\(hz)Hz  duration=\(duration)s")

        let capture = DisplayCapture(display: disp, fps: fps)
        try await capture.start()
        defer { Task { await capture.stop() } }

        // Wait for the first frame so we don't dump blanks.
        var haveFrame = false
        for _ in 0..<100 where !haveFrame {
            if capture.latestImage() != nil { haveFrame = true; break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard haveFrame else {
            await capture.stop()
            throw ProbeError("no frame delivered within timeout.")
        }

        let palette = Self.palette
        let pid = target.pid
        let start = Date()
        let tickNanos = UInt64(1_000_000_000 / max(1, hz))
        var frameIndex = 0
        var jsonlLines: [String] = []
        let jsonlURL = outDir.appendingPathComponent("rects.jsonl")

        while Date().timeIntervalSince(start) < duration {
            let tFrame = Date().timeIntervalSince(start)
            guard let base = capture.latestImage() else {
                try await Task.sleep(nanoseconds: tickNanos)
                continue
            }

            // Snapshot AX rects, convert AX points -> this display's pixel space.
            let axWindows = AXWindow.windows(pid: pid)
            var overlays: [OverlayRect] = []
            var rectJSON: [String] = []
            for w in axWindows {
                guard let f = w.frame() else { continue }
                let px = Coordinates.displayPixels(
                    fromAXRect: f,
                    displayOriginPoints: disp.originPoints,
                    scale: disp.scale)
                let color = palette[w.index % palette.count]
                overlays.append(
                    OverlayRect(
                        rect: px, label: "[\(w.index)] \(w.role)/\(w.subrole)", color: color))
                rectJSON.append(
                    """
                    {"index":\(w.index),"role":\(Self.q(w.role)),"subrole":\(Self.q(w.subrole)),\
                    "px":{"x":\(Int(px.origin.x)),"y":\(Int(px.origin.y)),\
                    "w":\(Int(px.size.width)),"h":\(Int(px.size.height))},\
                    "pt":{"x":\(Int(f.origin.x)),"y":\(Int(f.origin.y)),\
                    "w":\(Int(f.size.width)),"h":\(Int(f.size.height))}}
                    """)
            }

            let composed = ImageOutput.overlay(base: base, rects: overlays) ?? base
            let frameURL = outDir.appendingPathComponent(
                String(format: "frame_%04d.png", frameIndex))
            try ImageOutput.writePNG(composed, to: frameURL)

            let stats = capture.stats
            jsonlLines.append(
                """
                {"frame":\(frameIndex),"t":\(String(format: "%.4f", tFrame)),\
                "delivered":{"w":\(stats?.deliveredWidth ?? 0),"h":\(stats?.deliveredHeight ?? 0)},\
                "windows":[\(rectJSON.joined(separator: ","))]}
                """)

            frameIndex += 1
            try await Task.sleep(nanoseconds: tickNanos)
        }

        try jsonlLines.joined(separator: "\n").write(
            to: jsonlURL, atomically: true, encoding: .utf8)
        await capture.stop()

        print(String(repeating: "-", count: 56))
        print("  dumped \(frameIndex) frame(s) to \(outDir.path)")
        print("  rect log: \(jsonlURL.path)")
        print("  inspect the PNGs: does each outline sit exactly on the window's pixels?")
        print("  scrub frames during window motion: how many frames does the rect lag? (OQ-5)")

        Log.capture.notice(
            "probe \(target.name, privacy: .public) frames=\(frameIndex, privacy: .public)")
    }

    private static let palette: [CGColor] = [
        CGColor(red: 1, green: 0.2, blue: 0.2, alpha: 1),
        CGColor(red: 0.2, green: 1, blue: 0.3, alpha: 1),
        CGColor(red: 0.3, green: 0.6, blue: 1, alpha: 1),
        CGColor(red: 1, green: 0.9, blue: 0.2, alpha: 1),
        CGColor(red: 1, green: 0.4, blue: 1, alpha: 1),
        CGColor(red: 0.3, green: 1, blue: 1, alpha: 1),
    ]

    private static func q(_ s: String) -> String {
        "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
