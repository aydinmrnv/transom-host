import ArgumentParser

/// `capture` — run the single ScreenCaptureKit stream of the virtual display (stub).
///
/// One stream, one hardware encoder. The client crops per-window sub-rects out of
/// the shared texture; popups, sheets, and menus ride along for free because they
/// are already in the frame.
struct Capture: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "capture",
        abstract: "Start the shared ScreenCaptureKit stream of the virtual display. [not implemented]"
    )

    @Option(name: .long, help: "Display id to capture (defaults to the virtual display).")
    var display: Int?

    @Option(name: .long, help: "Target frame rate.")
    var fps: Int = 60

    func run() throws {
        Log.capture.notice("capture invoked (stub, fps=\(self.fps, privacy: .public))")
        print("capture: not implemented yet")
    }
}
