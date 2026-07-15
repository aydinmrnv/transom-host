import Foundation
import Testing

@testable import TransomKit

/// The wire protocol is a cross-language contract, so its JSON shape and framing
/// are pure and tested here. If one of these fails, the Rust client silently
/// stops understanding the host.
@Suite("WireProtocol")
struct WireProtocolTests {

    // MARK: round-trip

    private func roundTrip(_ message: ControlMessage) throws -> ControlMessage {
        try WireCodec.decodeControl(try WireCodec.encode(message))
    }
    private func roundTrip(_ message: ClientMessage) throws -> ClientMessage {
        try WireCodec.decodeClient(try WireCodec.encode(message))
    }

    @Test("every host->client message round-trips")
    func controlRoundTrips() throws {
        let messages: [ControlMessage] = [
            .hello(protocolVersion: 1, vdsSize: WireSize(w: 3840, h: 2160)),
            .windowCreated(
                id: 1, rect: WireRect(x: 0, y: 60, w: 1312, h: 844), title: "Xcode", kind: .normal),
            .windowMoved(id: 1, rect: WireRect(x: 1512, y: 60, w: 1312, h: 844)),
            .windowDestroyed(id: 7),
            .windowTitle(id: 1, title: "main.swift — edited"),
            .windowFocused(id: 1),
            .tileLayout(
                windows: [
                    WireWindow(id: 1, rect: WireRect(x: 0, y: 60, w: 100, h: 100)),
                    WireWindow(id: 2, rect: WireRect(x: 300, y: 60, w: 100, h: 100)),
                ], displaySize: WireSize(w: 3840, h: 2160)),
            .error(code: 42, message: "does not fit"),
        ]
        for m in messages {
            #expect(try roundTrip(m) == m)
        }
    }

    @Test("every client->host message round-trips")
    func clientRoundTrips() throws {
        let messages: [ClientMessage] = [
            .requestResize(id: 1, size: WireSize(w: 2560, h: 1440), phase: .live),
            .requestResize(id: 1, size: WireSize(w: 2560, h: 1440), phase: .end),
            .requestFocus(id: 3),
            .requestClose(id: 3),
        ]
        for m in messages {
            #expect(try roundTrip(m) == m)
        }
    }

    // MARK: JSON shape (the actual contract the Rust side sees)

    @Test("windowMoved serialises to the documented flat shape")
    func windowMovedShape() throws {
        let data = try WireCodec.encode(
            .windowMoved(id: 5, rect: WireRect(x: 10, y: 20, w: 30, h: 40)))
        let obj = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["type"] as? String == "windowMoved")
        #expect(obj["id"] as? UInt64 == 5)
        let rect = try #require(obj["rect"] as? [String: Any])
        #expect(rect["x"] as? Int == 10)
        #expect(rect["w"] as? Int == 30)
    }

    @Test("an unknown type is a decode error, not a crash")
    func unknownType() {
        let data = Data(#"{"type":"nonsense"}"#.utf8)
        #expect(throws: (any Error).self) { try WireCodec.decodeControl(data) }
    }

    // MARK: framing

    @Test("frame then FrameBuffer recovers the same payload")
    func frameRoundTrips() throws {
        let payload = Data("hello world".utf8)
        var buffer = FrameBuffer()
        buffer.append(WireCodec.frame(payload))
        #expect(try buffer.next() == payload)
        #expect(try buffer.next() == nil)
    }

    @Test("FrameBuffer reassembles across arbitrary chunk boundaries")
    func framesAcrossChunks() throws {
        let a = try WireCodec.framed(.windowFocused(id: 1))
        let b = try WireCodec.framed(.windowDestroyed(id: 2))
        let stream = a + b

        var buffer = FrameBuffer()
        var decoded: [ControlMessage] = []
        // Feed the concatenated stream one byte at a time — the worst case.
        for byte in stream {
            buffer.append(Data([byte]))
            while let payload = try buffer.next() {
                decoded.append(try WireCodec.decodeControl(payload))
            }
        }
        #expect(decoded == [.windowFocused(id: 1), .windowDestroyed(id: 2)])
    }

    @Test("multiple frames in one chunk all come out")
    func multipleFramesOneChunk() throws {
        let a = try WireCodec.framed(.windowFocused(id: 9))
        let b = try WireCodec.framed(.windowMoved(id: 9, rect: WireRect(x: 1, y: 2, w: 3, h: 4)))
        var buffer = FrameBuffer()
        buffer.append(a + b)
        // Pop into locals first: `next()` is mutating and cannot be called inside
        // the #require/#expect macro expansion.
        let firstPayload = try #require(try buffer.next())
        let secondPayload = try #require(try buffer.next())
        let thirdPayload = try buffer.next()
        #expect(try WireCodec.decodeControl(firstPayload) == .windowFocused(id: 9))
        #expect(
            try WireCodec.decodeControl(secondPayload)
                == .windowMoved(id: 9, rect: WireRect(x: 1, y: 2, w: 3, h: 4)))
        #expect(thirdPayload == nil)
    }

    @Test("an over-large frame length is rejected, not buffered")
    func rejectsHugeFrame() {
        var buffer = FrameBuffer(maxFrameLength: 16)
        // Claim a 1 MB frame with only the header present.
        buffer.append(Data([0x00, 0x0F, 0x42, 0x40]))
        #expect(throws: FrameBuffer.FrameError.self) { try buffer.next() }
    }

    // MARK: video wire

    @Test("video config round-trips")
    func videoConfigRoundTrips() {
        let hvcc = Data([1, 2, 3, 4, 5])
        #expect(VideoWire.decode(VideoWire.encodeConfig(hvcc: hvcc)) == .config(hvcc: hvcc))
    }

    @Test("video frame round-trips with its header")
    func videoFrameRoundTrips() {
        let payload = Data([0xAB, 0xCD, 0xEF])
        let encoded = VideoWire.encodeFrame(
            seq: 12_345, ptsMicros: 9_876_543, keyframe: true, data: payload)
        #expect(
            VideoWire.decode(encoded)
                == .frame(seq: 12_345, ptsMicros: 9_876_543, keyframe: true, data: payload))
    }
}
