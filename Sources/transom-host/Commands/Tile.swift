import ArgumentParser

/// `tile` — arrange all managed windows non-overlapping on the virtual display (stub).
///
/// The virtual display is a compositing scratch space: every window must be laid
/// out so it always renders and is never occluded. This command owns that packing.
struct Tile: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tile",
        abstract: "Pack managed windows non-overlapping on the virtual display. [not implemented]"
    )

    @Option(name: .long, help: "Packing strategy (e.g. shelf, grid).")
    var strategy: String = "shelf"

    @Option(name: .long, help: "Gap in points between tiled windows.")
    var gap: Int = 0

    func run() throws {
        Log.general.notice("tile invoked (stub, strategy=\(self.strategy, privacy: .public))")
        print("tile: not implemented yet")
    }
}
