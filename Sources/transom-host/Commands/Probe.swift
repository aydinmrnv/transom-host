import ArgumentParser

/// `probe` — run the correctness experiments that de-risk the architecture (stub).
///
/// The open questions in `docs/architecture.md` (do NSMenu popups show up in SCK
/// capture? are AX geometry writes honored exactly or clamped? what is the tiling
/// budget?) get answered by probes here. These are separate follow-up tasks.
struct Probe: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "probe",
        abstract: "Run architecture de-risking experiments. [not implemented]"
    )

    @Argument(help: "Which probe to run (e.g. menu-capture, ax-geometry, tile-budget).")
    var name: String?

    func run() throws {
        Log.general.notice("probe invoked (stub, name=\(self.name ?? "-", privacy: .public))")
        print("probe: not implemented yet")
    }
}
