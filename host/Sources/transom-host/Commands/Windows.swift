import ApplicationServices
import ArgumentParser
import Foundation
import TransomKit

/// `windows <app>` — list an app's AX windows: index, title, frame (AX points),
/// role, subrole, and whether AX reports the window as resizable.
///
/// The index is what `place`/`tile` target. The frame is in AX global space
/// (points, top-left, Y down — I-3).
struct Windows: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "windows",
        abstract: "List an app's AX windows: title, frame, role, subrole, resizable.")

    @Argument(help: "Target app: a name like \"Xcode\" or a bundle id.")
    var app: String

    @Flag(name: .long, help: "Emit JSON instead of a table.")
    var json = false

    func run() throws {
        guard AXIsProcessTrusted() else {
            throw ProbeError(
                "Accessibility is not granted. Run `transom-host doctor` for guidance.")
        }

        let target: TargetApp
        switch AppResolver.resolve(app) {
        case .success(let t): target = t
        case .failure(let e): throw e
        }

        let windows = AXWindow.windows(pid: target.pid).map { $0.info() }
        Log.ax.notice("windows: \(target.name, privacy: .public) has \(windows.count) window(s)")

        if json {
            print(Self.jsonString(windows))
            return
        }

        print("\(target.name) (pid \(target.pid)) — \(windows.count) AX window(s)")
        if windows.isEmpty {
            print("  (none — the app may have no open windows, or AX is hiding them)")
            return
        }
        print("  idx  resiz  role/subrole                frame (AX pt)                 title")
        for w in windows {
            let f = w.frame
            let frameStr =
                f.isNull
                ? "(no frame)"
                : "(\(int(f.origin.x)),\(int(f.origin.y))) "
                    + "\(int(f.size.width))x\(int(f.size.height))"
            let resiz = w.resizable ? "yes" : "no "
            let rs = "\(w.role)/\(w.subrole)".padding(
                toLength: 26, withPad: " ", startingAt: 0)
            print(
                "  \(String(format: "%3d", w.index))  \(resiz)    " + rs + "  "
                    + frameStr.padding(toLength: 28, withPad: " ", startingAt: 0)
                    + "  \(w.title)")
        }
    }

    private func int(_ v: CGFloat) -> Int { Int(v.rounded()) }

    private static func jsonString(_ windows: [AXWindowInfo]) -> String {
        let objs = windows.map { w -> String in
            let f = w.frame
            return """
                {"index":\(w.index),"title":\(quote(w.title)),\
                "role":\(quote(w.role)),"subrole":\(quote(w.subrole)),\
                "resizable":\(w.resizable),\
                "x":\(Int(f.origin.x)),"y":\(Int(f.origin.y)),\
                "w":\(Int(f.size.width)),"h":\(Int(f.size.height))}
                """
        }
        return "[\(objs.joined(separator: ","))]"
    }

    private static func quote(_ s: String) -> String {
        let escaped =
            s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
