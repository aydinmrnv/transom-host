import CoreGraphics

/// One attached display, reported the way Transom reasons about displays:
/// **pixels are first-class**, points are secondary, and the scale factor that
/// relates them is explicit (never assumed 2x — invariant I-1).
public struct DisplayInfo: Sendable {
    /// CoreGraphics display id. This is the id BetterDisplay hands you and the id
    /// every command targets.
    public let id: CGDirectDisplayID

    /// Origin in the global point space (AX space), top-left, Y down.
    public let originPoints: CGPoint

    /// Size in points, per the current display mode.
    public let sizePoints: CGSize

    /// Native pixel dimensions of the current mode. This is the number
    /// `SCStreamConfiguration.width/height` MUST equal, or SCK is scaling and
    /// I-1 is violated.
    public let pixelWidth: Int
    public let pixelHeight: Int

    /// Backing scale factor: pixels per point. 2.0 on Retina, 1.0 otherwise.
    public let scale: Double

    /// Whether this is the main display. The Transom virtual display must be main
    /// (architecture.md 3.2); AX global origin lives at this display's top-left.
    public let isMain: Bool

    /// Pixel bounds in the global pixel space (origin scaled from points).
    public var pixelBounds: CGRect {
        CGRect(
            x: originPoints.x * scale,
            y: originPoints.y * scale,
            width: Double(pixelWidth),
            height: Double(pixelHeight)
        )
    }
}

public enum Displays {
    /// Enumerate all active displays. Returns them in CoreGraphics order (main
    /// first is not guaranteed; check `isMain`).
    public static func all() -> [DisplayInfo] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
            return []
        }
        let mainID = CGMainDisplayID()
        return ids.prefix(Int(count)).map { id in
            let bounds = CGDisplayBounds(id)
            let (pw, ph, scale) = pixelGeometry(of: id, pointSize: bounds.size)
            return DisplayInfo(
                id: id,
                originPoints: bounds.origin,
                sizePoints: bounds.size,
                pixelWidth: pw,
                pixelHeight: ph,
                scale: scale,
                isMain: id == mainID
            )
        }
    }

    /// Look up a single display by id, or nil if it is not active.
    public static func byID(_ id: CGDirectDisplayID) -> DisplayInfo? {
        all().first { $0.id == id }
    }

    /// Native pixel size and backing scale from the display's current mode.
    /// `CGDisplayCopyDisplayMode` distinguishes points (`.width`) from pixels
    /// (`.pixelWidth`); their ratio is the scale factor.
    private static func pixelGeometry(
        of id: CGDirectDisplayID, pointSize: CGSize
    ) -> (Int, Int, Double) {
        guard let mode = CGDisplayCopyDisplayMode(id), mode.width > 0 else {
            return (Int(pointSize.width), Int(pointSize.height), 1.0)
        }
        let scale = Double(mode.pixelWidth) / Double(mode.width)
        return (mode.pixelWidth, mode.pixelHeight, scale)
    }
}
