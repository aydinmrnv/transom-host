import ArgumentParser
import CoreGraphics
import Foundation
import TransomKit

/// `capture <display> --out <path>` — run one SCK stream of a display, dump a
/// PNG, and log the **actual** delivered dimensions and pixel format.
///
/// The load-bearing check (I-1): the stream is configured at the display's exact
/// native pixel size, and this command verifies the delivered buffer matches. If
/// `SCStreamConfiguration.width/height` does not equal the display's pixel size,
/// SCK is scaling and I-1 is already violated.
struct Capture: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "capture",
        abstract: "SCK stream a display, dump a PNG, log actual dims and pixel format.")

    @Argument(help: "Display id, as printed by `displays`.")
    var display: UInt32

    @Option(name: .long, help: "Output PNG path.")
    var out: String

    @Option(name: .long, help: "Target frame rate.")
    var fps: Int = 60

    func run() async throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw ProbeError(
                "Screen Recording is not granted. Run `transom-host doctor` for guidance.")
        }
        guard let disp = TransomKit.Displays.byID(display) else {
            throw ProbeError("no active display with id \(display). See `displays`.")
        }

        print("capture: display \(display), native \(disp.pixelWidth)x\(disp.pixelHeight) px")

        let capture = DisplayCapture(display: disp, fps: fps)
        try await capture.start()

        // Wait for the first complete frame (bounded).
        guard let image = try await waitForFrame(capture) else {
            await capture.stop()
            throw ProbeError("no frame delivered within timeout — SCK produced nothing.")
        }
        let stats = capture.stats
        await capture.stop()

        let url = URL(fileURLWithPath: out)
        try ImageOutput.writePNG(image, to: url)

        print("  wrote \(url.path)  (\(image.width)x\(image.height) px)")
        if let s = stats {
            print("  configured : \(s.configuredWidth)x\(s.configuredHeight) px")
            print("  delivered  : \(s.deliveredWidth)x\(s.deliveredHeight) px")
            print("  pixelFormat: \(s.pixelFormatString)")
            print(String(repeating: "-", count: 56))
            if s.matchesNativePixels {
                print("  I-1 CHECK  : PASS — SCK delivered exact native pixels, no scaling.")
            } else {
                print(
                    "  I-1 CHECK  : FAIL — delivered size != native size. "
                        + "SCK is scaling; I-1 is violated.")
            }
        }

        Log.capture.notice(
            "capture display=\(self.display, privacy: .public) wrote=\(url.path, privacy: .public)")
    }

    /// Poll for the first frame for up to ~5 seconds.
    private func waitForFrame(_ capture: DisplayCapture) async throws -> CGImage? {
        for _ in 0..<100 {
            if let image = capture.latestImage() { return image }
            try await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        }
        return nil
    }
}
