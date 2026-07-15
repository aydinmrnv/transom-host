import ApplicationServices
import ArgumentParser
import CoreGraphics
import Foundation
import TransomKit

/// `tile <app> <display>` — pack an app's windows non-overlapping on a display
/// and report the layout and whether it fits.
///
/// Per **I-5**, windows never overlap. If a window cannot fit, that is an error
/// to surface, **not** an occasion to overlap. This uses a simple shelf packer
/// (left-to-right, wrap to a new row) at each window's current size — the point
/// is to exercise the non-overlap guarantee and the tiling budget
/// (architecture.md 3.3), not to be a clever bin-packer.
struct Tile: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tile",
        abstract: "Tile an app's windows non-overlapping on a display; report fit.")

    @Argument(help: "Target app: a name like \"Xcode\" or a bundle id.")
    var app: String

    @Argument(help: "Display id, as printed by `displays`.")
    var display: UInt32

    @Option(name: .long, help: "Gap in points between tiled windows.")
    var gap: Int = 0

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
        guard !windows.isEmpty else {
            throw ProbeError("\(target.name) has no AX windows to tile.")
        }

        let dw = disp.sizePoints.width
        let dh = disp.sizePoints.height
        let g = CGFloat(gap)

        print("tile: \(target.name) on display \(display) (\(Int(dw))x\(Int(dh)) pt), gap=\(gap)")
        print(String(repeating: "-", count: 72))

        // Shelf-pack using each window's current size.
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var targets: [(win: AXWindow, rect: CGRect)] = []
        var fits = true

        for win in windows {
            guard let size = win.size() else {
                print("  window[\(win.index)] \"\(win.title)\": AX reports no size, skipping")
                continue
            }
            let w = size.width
            let h = size.height

            if w > dw || h > dh {
                print(
                    "  window[\(win.index)] \"\(win.title)\": "
                        + "\(Int(w))x\(Int(h)) is larger than the display — CANNOT FIT (I-5)")
                fits = false
                continue
            }
            // Wrap to a new shelf if it would run off the right edge.
            if cursorX + w > dw {
                cursorX = 0
                cursorY += rowHeight + g
                rowHeight = 0
            }
            if cursorY + h > dh {
                print(
                    "  window[\(win.index)] \"\(win.title)\": "
                        + "no vertical room left — CANNOT FIT without overlap (I-5)")
                fits = false
                continue
            }
            targets.append((win, CGRect(x: cursorX, y: cursorY, width: w, height: h)))
            cursorX += w + g
            rowHeight = max(rowHeight, h)
        }

        // Apply and read back.
        var actualRects: [(idx: Int, rect: CGRect)] = []
        for t in targets {
            let globalPos = CGPoint(
                x: disp.originPoints.x + t.rect.origin.x,
                y: disp.originPoints.y + t.rect.origin.y)
            let result = t.win.place(position: globalPos, size: t.rect.size)
            let actual: CGRect
            if let ap = result.actualPosition, let asz = result.actualSize {
                // Report actual back in display-local coordinates.
                actual = CGRect(
                    x: ap.x - disp.originPoints.x, y: ap.y - disp.originPoints.y,
                    width: asz.width, height: asz.height)
            } else {
                actual = .null
            }
            actualRects.append((t.win.index, actual))
            let exactTag = result.exact ? "exact" : "Δ"
            print(
                "  window[\(t.win.index)] \"\(t.win.title)\"\n"
                    + "    target : (\(i(t.rect.origin.x)),\(i(t.rect.origin.y))) "
                    + "\(i(t.rect.size.width))x\(i(t.rect.size.height))\n"
                    + "    actual : "
                    + (actual.isNull
                        ? "(AX would not report back)"
                        : "(\(i(actual.origin.x)),\(i(actual.origin.y))) "
                            + "\(i(actual.size.width))x\(i(actual.size.height))  [\(exactTag)]"))
        }

        // Verify the ACTUAL rects (post-clamp) still don't overlap — I-5 is about
        // what really happened, not what we intended.
        var overlaps = false
        for a in 0..<actualRects.count {
            for b in (a + 1)..<actualRects.count {
                let ra = actualRects[a].rect
                let rb = actualRects[b].rect
                if !ra.isNull, !rb.isNull, ra.intersects(rb) {
                    overlaps = true
                    print(
                        "  OVERLAP after readback: window[\(actualRects[a].idx)] "
                            + "and window[\(actualRects[b].idx)] intersect")
                }
            }
        }

        print(String(repeating: "-", count: 72))
        print("  layout fits within display: \(fits ? "YES" : "NO")")
        print("  actual rects non-overlapping (I-5): \(overlaps ? "NO — see above" : "YES")")
        if !fits {
            print("  -> tiling budget exceeded for this window set (architecture.md 3.3)")
        }

        Log.general.notice(
            "tile \(target.name, privacy: .public) fits=\(fits, privacy: .public) overlap=\(overlaps, privacy: .public)"
        )

        if !fits || overlaps { throw ExitCode.failure }
    }

    private func i(_ v: CGFloat) -> Int { Int(v.rounded()) }
}
