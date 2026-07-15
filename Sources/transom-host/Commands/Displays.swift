import ArgumentParser

/// `displays` — machine-readable display enumeration (stub).
///
/// `doctor` already prints displays for humans; this command will emit the same
/// data as stable JSON for the client's display picker.
struct Displays: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "displays",
        abstract: "List displays available for capture. [not implemented]"
    )

    @Flag(name: .long, help: "Emit JSON instead of a table.")
    var json = false

    func run() throws {
        Log.general.notice("displays invoked (stub, json=\(self.json, privacy: .public))")
        print("displays: not implemented yet")
    }
}
