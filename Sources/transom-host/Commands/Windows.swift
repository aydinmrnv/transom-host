import ArgumentParser

/// `windows` — enumerate on-screen app windows and their AX geometry (stub).
struct Windows: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "windows",
        abstract: "List app windows and their geometry. [not implemented]"
    )

    @Option(name: .long, help: "Only windows belonging to this bundle identifier.")
    var app: String?

    @Flag(name: .long, help: "Emit JSON instead of a table.")
    var json = false

    func run() throws {
        Log.general.notice("windows invoked (stub, app=\(self.app ?? "*", privacy: .public))")
        print("windows: not implemented yet")
    }
}
