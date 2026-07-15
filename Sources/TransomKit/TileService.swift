import ApplicationServices
import CoreGraphics
import Foundation

/// Drives the pure `Tiler` against a live app through AX: read window sizes,
/// compute a layout, write positions, and let the caller read the actual result
/// back via the watcher (I-4). Shared by the `tile` command (which additionally
/// reports deltas) and `serve` (which tiles once at startup so the streamed
/// windows are non-overlapping, I-5).
public enum TileService {

    /// Tile every `AXWindow`-role window of `pid` on `display` with `gutter`
    /// pixels between tiles. Returns the number placed, or the tiler's typed error
    /// if the set does not fit.
    @discardableResult
    public static func tile(pid: pid_t, display: DisplayInfo, gutter: Int)
        -> Result<Int, TilerError>
    {
        var placeable: [(win: AXWindow, sizePoints: CGSize, sizePixels: TileSize)] = []
        for win in AXWindow.windows(pid: pid) where win.role == (kAXWindowRole as String) {
            guard let size = win.size() else { continue }
            let px = TileSize(
                width: Int(
                    Coordinates.vdsPixels(fromAXPoints: size.width, scale: display.scale).rounded()),
                height: Int(
                    Coordinates.vdsPixels(fromAXPoints: size.height, scale: display.scale).rounded()
                ))
            placeable.append((win, size, px))
        }
        guard !placeable.isEmpty else { return .success(0) }

        let displaySize = TileSize(width: display.pixelWidth, height: display.pixelHeight)
        switch Tiler.layout(
            windows: placeable.map(\.sizePixels), display: displaySize, gutter: gutter)
        {
        case .failure(let error):
            return .failure(error)
        case .success(let rects):
            for (placement, rect) in zip(placeable, rects) {
                let axRect = Coordinates.axGlobalRect(
                    fromDisplayPixels: CGRect(
                        x: CGFloat(rect.x), y: CGFloat(rect.y),
                        width: CGFloat(rect.width), height: CGFloat(rect.height)),
                    displayOriginPoints: display.originPoints,
                    scale: display.scale)
                _ = placement.win.place(position: axRect.origin, size: placement.sizePoints)
            }
            return .success(placeable.count)
        }
    }
}
