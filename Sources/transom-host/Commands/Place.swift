import ApplicationServices
import ArgumentParser
import CoreGraphics
import Foundation
import TransomKit

/// `place <app> <idx> <display> <x> <y> <w> <h>` — set one window's AXPosition
/// and AXSize, **read both back, and report the delta**.
///
/// The delta is the entire point of this command (I-4, OQ-2). "It worked" is not
/// the output; "requested 2560x1440, got 2560x1438" is. macOS may clamp to
/// display bounds, round to even pixels, or enforce an app minimum size — this
/// command exists to measure exactly that.
///
/// Units: x/y/w/h are AX **points**, which is what the AX API natively takes.
/// x/y are interpreted as local to `<display>` (its origin is added to reach AX
/// global space), so on the main display they are AX-global as-is.
struct Place: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "place",
        abstract: "Set a window's AXPosition/AXSize, read back, report the delta.")

    @Argument(help: "Target app: a name like \"Xcode\" or a bundle id.")
    var app: String

    @Argument(help: "Window index, as printed by `windows`.")
    var index: Int

    @Argument(help: "Display id, as printed by `displays`.")
    var display: UInt32

    @Argument(help: "Origin x (AX points, local to the display).")
    var x: Int

    @Argument(help: "Origin y (AX points, local to the display).")
    var y: Int

    @Argument(help: "Width (AX points).")
    var width: Int

    @Argument(help: "Height (AX points).")
    var height: Int

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

        guard let disp = TransomKit.Displays.byID(display) else {
            throw ProbeError("no active display with id \(display). See `displays`.")
        }

        let windows = AXWindow.windows(pid: target.pid)
        guard index >= 0, index < windows.count else {
            throw ProbeError(
                "window index \(index) out of range (app has \(windows.count) window(s)).")
        }
        let window = windows[index]

        // Local display point coords -> AX global points (display origin offset).
        let globalX = disp.originPoints.x + CGFloat(x)
        let globalY = disp.originPoints.y + CGFloat(y)
        let requestPos = CGPoint(x: globalX, y: globalY)
        let requestSize = CGSize(width: CGFloat(width), height: CGFloat(height))

        let before = window.frame()
        let result = window.place(position: requestPos, size: requestSize)

        print("place: \(target.name) window[\(index)] \"\(window.title)\" on display \(display)")
        if let before {
            print(
                "  before   : pos=(\(i(before.origin.x)),\(i(before.origin.y))) "
                    + "size=\(i(before.size.width))x\(i(before.size.height))")
        }
        print("  set AXSize     -> \(axErr(result.setSizeError))")
        print("  set AXPosition -> \(axErr(result.setPositionError))")

        print(
            "  requested: pos=(\(i(requestPos.x)),\(i(requestPos.y))) "
                + "size=\(width)x\(height)")
        if let ap = result.actualPosition, let asz = result.actualSize {
            print(
                "  actual   : pos=(\(i(ap.x)),\(i(ap.y))) "
                    + "size=\(i(asz.width))x\(i(asz.height))")
        } else {
            print("  actual   : (AX would not report position/size after the write)")
        }

        // The headline: the delta.
        print(String(repeating: "-", count: 60))
        if let pd = result.positionDelta {
            let tag = (pd.x == 0 && pd.y == 0) ? "exact" : "CLAMPED/MOVED"
            print("  position delta: (\(i(pd.x)),\(i(pd.y)))  [\(tag)]")
        }
        if let sd = result.sizeDelta {
            let tag = (sd.width == 0 && sd.height == 0) ? "exact" : "CLAMPED/ROUNDED"
            print(
                "  size delta    : "
                    + "requested \(width)x\(height), "
                    + "got \(i((requestSize.width + sd.width)))x\(i((requestSize.height + sd.height)))"
                    + "  (Δ \(i(sd.width))x\(i(sd.height)))  [\(tag)]")
        }
        print("  OQ-2: writes honored exactly? \(result.exact ? "YES" : "NO — see deltas above")")

        Log.ax.notice(
            "place \(target.name, privacy: .public)[\(self.index)] exact=\(result.exact, privacy: .public)"
        )
    }

    private func i(_ v: CGFloat) -> Int { Int(v.rounded()) }

    private func axErr(_ e: AXError) -> String {
        e == .success ? "ok" : "AXError(\(e.rawValue))"
    }
}
