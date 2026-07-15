import AppKit
import SwiftUI
import TransomKit

/// Transom Probe — the diagnostic app (issue Part 2).
///
/// This is **not** the product. It is a one-window instrument whose whole job is
/// to answer OQ-1 visually: open Xcode's Product menu and *see*, live, whether
/// the menu lands in the ScreenCaptureKit capture and whether AX puts a rect
/// around it. It exists as a bundle (not just the CLI) for two reasons: a stable
/// bundle id gets its own TCC identity, and a live view answers a visual
/// question in seconds where PNG dumps are slow and ambiguous.
@main
struct TransomProbeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Transom Probe", id: "main") {
            ContentView()
                .frame(minWidth: 900, minHeight: 640)
        }
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure we are a regular, focusable app even when launched oddly.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Log.app.info("Transom Probe launched")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
