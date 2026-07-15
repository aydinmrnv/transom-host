import ArgumentParser

/// `menuwatch` — observe the global menu bar for the focused app (stub).
///
/// macOS apps put their menus in the global menu bar, not in-window. Lifting a
/// single window onto the client leaves it menu-less, so the client needs a live
/// view of the focused app's menu tree. This command will stream it.
struct MenuWatch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "menuwatch",
        abstract: "Stream the focused app's global menu bar structure. [not implemented]"
    )

    @Option(name: .long, help: "Only watch this bundle identifier.")
    var app: String?

    func run() throws {
        Log.ax.notice("menuwatch invoked (stub, app=\(self.app ?? "*", privacy: .public))")
        print("menuwatch: not implemented yet")
    }
}
