import ApplicationServices
import ArgumentParser
import CoreGraphics
import Foundation
import TransomKit

/// `menuwatch <app>` — **the kill-question command (OQ-1).**
///
/// Registers an `AXObserver` on the target app and prints every window and menu
/// that AX announces — created, destroyed, opened, closed — with its frame,
/// role, subrole, and a timestamp. Open Xcode's Product menu and a
/// code-completion popup and watch what shows up.
///
/// If `NSMenu` popups do not surface here with a usable frame and a
/// distinguishable role/subrole, they will not surface in an SCK capture either,
/// and Transom does not work. This command exists to answer that on day one.
struct MenuWatch: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "menuwatch",
        abstract: "Observe window/menu create/destroy/open/close for an app (answers OQ-1).")

    @Argument(help: "Target app: a name like \"Xcode\" or a bundle id.")
    var app: String

    @Option(name: .long, help: "Auto-stop after N seconds (default: run until Ctrl-C).")
    var seconds: Double?

    func run() throws {
        // Stream output live: stdout is block-buffered when redirected to a file
        // or pipe, so without this a Ctrl-C / kill would drop everything observed.
        setvbuf(stdout, nil, _IONBF, 0)

        guard AXIsProcessTrusted() else {
            throw ProbeError(
                "Accessibility is not granted to THIS process's launcher. "
                    + "Run `transom-host doctor` and grant the terminal (or run the .app).")
        }

        let target: TargetApp
        switch AppResolver.resolve(app) {
        case .success(let t): target = t
        case .failure(let e): throw e
        }

        let mainScale = TransomKit.Displays.all().first(where: { $0.isMain })?.scale ?? 1.0

        print("menuwatch: \(target.name) (pid \(target.pid), \(target.bundleID ?? "no bundle id"))")
        print("main-display scale: \(String(format: "%.2f", mainScale))x  (px = pt * scale)")
        print("watching. open the app's menus / completion popups. Ctrl-C to stop.")
        print(String(repeating: "-", count: 78))
        print("     t(s)  event                    role/subrole            frame (AX pt)")

        let watcher = MenuWatcher(pid: target.pid, mainScale: mainScale)
        try watcher.start()

        if let seconds {
            Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
        }

        // Block on the run loop; AX notifications are delivered here.
        CFRunLoopRun()
        print(String(repeating: "-", count: 78))
        print("menuwatch: stopped.")
    }
}

/// Owns the `AXObserver` and formats each notification. Not actor-isolated: the
/// AX callback is a C function delivered on this thread's run loop, and all it
/// does is read attributes and print.
final class MenuWatcher {
    private let pid: pid_t
    private let mainScale: Double
    private let appElement: AXUIElement
    private var observer: AXObserver?
    private let startTime = Date()

    /// Notifications we ask AX about. Menu open/close is the direct OQ-1 signal;
    /// window create/destroy catches sheets and separate popup windows.
    private static let notifications: [String] = [
        kAXWindowCreatedNotification,
        kAXUIElementDestroyedNotification,
        kAXMenuOpenedNotification,
        kAXMenuClosedNotification,
        kAXFocusedUIElementChangedNotification,
        kAXFocusedWindowChangedNotification,
        kAXWindowMiniaturizedNotification,
    ]

    init(pid: pid_t, mainScale: Double) {
        self.pid = pid
        self.mainScale = mainScale
        self.appElement = AXWindow.application(pid: pid)
    }

    func start() throws {
        var obs: AXObserver?
        let err = AXObserverCreate(pid, menuWatchCallback, &obs)
        guard err == .success, let obs else {
            throw ProbeError("AXObserverCreate failed: \(err.rawValue)")
        }
        self.observer = obs

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.notifications {
            let addErr = AXObserverAddNotification(obs, appElement, name as CFString, refcon)
            if addErr != .success && addErr != .notificationAlreadyRegistered {
                // Not fatal: some apps don't emit some notifications. Note it.
                FileHandle.standardError.write(
                    Data("  (note: could not register \(name): \(addErr.rawValue))\n".utf8))
            }
        }

        CFRunLoopAddSource(
            CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)
    }

    /// Called from the C trampoline for every notification.
    func handle(element: AXUIElement, notification: String) {
        let t = Date().timeIntervalSince(startTime)
        let win = AXWindow(element: element, index: -1)
        let role = win.role
        let subrole = win.subrole
        let title = win.title
        let frameStr: String
        if let f = win.frame() {
            let px = Coordinates.displayPixels(
                fromAXRect: f, displayOriginPoints: .zero, scale: mainScale)
            frameStr =
                "(\(int(f.origin.x)),\(int(f.origin.y))) \(int(f.size.width))x\(int(f.size.height))"
                + "  [px \(int(px.size.width))x\(int(px.size.height))]"
        } else {
            frameStr = "(no frame)"
        }

        let event = shortName(notification)
        let roleField = "\(role)/\(subrole)".padding(
            toLength: 22, withPad: " ", startingAt: 0)
        let titleSuffix = title.isEmpty ? "" : "  \"\(title)\""
        print(
            String(format: "%9.3f  ", t)
                + event.padding(toLength: 24, withPad: " ", startingAt: 0)
                + " " + roleField + "  " + frameStr + titleSuffix)

        Log.ax.info(
            "menuwatch \(notification, privacy: .public) role=\(role, privacy: .public)")
    }

    private func shortName(_ n: String) -> String {
        n.replacingOccurrences(of: "AX", with: "")
            .replacingOccurrences(of: "Notification", with: "")
    }

    private func int(_ v: CGFloat) -> Int { Int(v.rounded()) }
}

/// C trampoline. Cannot capture context, so `refcon` carries the `MenuWatcher`.
private func menuWatchCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let watcher = Unmanaged<MenuWatcher>.fromOpaque(refcon).takeUnretainedValue()
    watcher.handle(element: element, notification: notification as String)
}
