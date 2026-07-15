import ArgumentParser

/// `place` — set one window's position and size via the Accessibility API (stub).
///
/// This is the write half of geometry mirroring: the client says "the window is
/// now N pixels wide", and we push exactly that size onto the Mac window so the
/// app relayouts natively. See `docs/architecture.md`.
struct Place: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "place",
        abstract: "Move/resize a window on the virtual display via AX. [not implemented]"
    )

    @Option(name: .long, help: "Target window id (as reported by `windows`).")
    var window: Int?

    @Option(name: .long, help: "Origin x, in points, on the virtual display.")
    var x: Int?

    @Option(name: .long, help: "Origin y, in points, on the virtual display.")
    var y: Int?

    @Option(name: .long, help: "Width in points.")
    var width: Int?

    @Option(name: .long, help: "Height in points.")
    var height: Int?

    func run() throws {
        Log.ax.notice("place invoked (stub, window=\(self.window ?? -1, privacy: .public))")
        print("place: not implemented yet")
    }
}
