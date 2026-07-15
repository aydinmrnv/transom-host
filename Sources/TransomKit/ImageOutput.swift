import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A labelled rectangle to stroke over a captured frame, in **SCK pixel space**
/// (top-left origin, Y down) — the same space the frame pixels live in.
public struct OverlayRect: Sendable {
    public let rect: CGRect
    public let label: String
    public let color: CGColor

    public init(rect: CGRect, label: String, color: CGColor) {
        self.rect = rect
        self.label = label
        self.color = color
    }
}

public enum ImageOutput {

    /// Write a CGImage to disk as a PNG. Lossless — this is a diagnostic
    /// instrument and must not resample (I-1).
    public static func writePNG(_ image: CGImage, to url: URL) throws {
        guard
            let dest = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw ImageOutputError.destinationFailed(url)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw ImageOutputError.writeFailed(url)
        }
    }

    /// Draw colored outlines (with labels) on top of a captured frame.
    ///
    /// The context is flipped to a top-left origin so it shares SCK pixel space
    /// with the incoming rects: no Y flip games, no mirrored-frame bug (I-3).
    public static func overlay(base: CGImage, rects: [OverlayRect]) -> CGImage? {
        let width = base.width
        let height = base.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let ctx = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // Flip to top-left origin, Y down, matching SCK/AX pixel space.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        ctx.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))

        let lineWidth = max(2.0, CGFloat(width) / 800.0)
        for r in rects {
            ctx.setStrokeColor(r.color)
            ctx.setLineWidth(lineWidth)
            ctx.stroke(r.rect)
            drawLabel(r.label, at: r.rect.origin, color: r.color, in: ctx, scale: width)
        }
        return ctx.makeImage()
    }

    /// Draw a text label. CoreText draws with a bottom-left baseline, so within
    /// our flipped (top-left) context we flip locally just around the glyph run.
    private static func drawLabel(
        _ text: String, at point: CGPoint, color: CGColor, in ctx: CGContext, scale: Int
    ) {
        let fontSize = max(11.0, CGFloat(scale) / 130.0)
        let font = CTFontCreateWithName("Menlo" as CFString, fontSize, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attributed)

        ctx.saveGState()
        // Undo the global flip locally so glyphs render upright.
        ctx.translateBy(x: point.x + 3, y: point.y + fontSize + 3)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = .zero
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}

public enum ImageOutputError: Error, CustomStringConvertible {
    case destinationFailed(URL)
    case writeFailed(URL)

    public var description: String {
        switch self {
        case .destinationFailed(let url): return "could not create PNG at \(url.path)"
        case .writeFailed(let url): return "could not finalize PNG at \(url.path)"
        }
    }
}
