import Foundation

/// The video channel server (issue #3 Phase 3, second connection): streams
/// encoded HEVC frames to at most one connected client.
///
/// This is the "frames may be dropped, never delayed" channel (protocol.md §1).
/// The caller feeds frames through a small most-recent buffer, so if the client
/// or link stalls, old frames are dropped rather than queued. On connect (and
/// again on reconnect) the parameter sets are sent before the first frame,
/// because an `hvc1` stream is undecodable without them.
public actor VideoServer {
    private var active: TCPTransport?
    private var sentConfig = false
    private var seq: UInt64 = 0
    private let hvccProvider: @Sendable () -> Data?

    /// - Parameter hvccProvider: returns the encoder's `hvcC` parameter sets once
    ///   the first frame has been encoded (nil before then).
    public init(hvccProvider: @escaping @Sendable () -> Data?) {
        self.hvccProvider = hvccProvider
    }

    public func serve(listener: TCPListener) async {
        for await transport in listener.connections {
            await handle(transport)
        }
    }

    private func handle(_ transport: TCPTransport) async {
        active = transport
        sentConfig = false
        Log.encode.notice("video: client connected")
        // The client sends nothing on this channel; the receive loop just detects
        // disconnect so the host can stop targeting a dead socket.
        do {
            while try await transport.receiveFrame() != nil {}
        } catch {
            // fall through to cleanup
        }
        Log.encode.notice("video: client disconnected")
        if active === transport { active = nil }
        await transport.close()
    }

    /// Send one encoded frame to the connected client, if any. Config is sent
    /// lazily before the first frame of a connection.
    public func send(_ frame: HEVCEncoder.EncodedFrame) async {
        guard let active else { return }
        do {
            if !sentConfig, let hvcc = hvccProvider() {
                try await active.send(VideoWire.encodeConfig(hvcc: hvcc))
                sentConfig = true
            }
            let ptsMicros =
                frame.pts.seconds.isFinite ? UInt64(max(0, frame.pts.seconds * 1_000_000)) : 0
            try await active.send(
                VideoWire.encodeFrame(
                    seq: seq, ptsMicros: ptsMicros, keyframe: frame.isKeyframe, data: frame.data))
            seq += 1
        } catch {
            self.active = nil
        }
    }
}
