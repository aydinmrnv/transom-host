import ArgumentParser
import Foundation
import TransomKit

/// `displays` — enumerate displays with **pixel** bounds, scale, and which is
/// main. Pixels are reported first because the whole pipeline reasons in pixels
/// (I-1); points are secondary.
struct Displays: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "displays",
        abstract: "List displays: id, pixel bounds, scale factor, which is main.")

    @Flag(name: .long, help: "Emit JSON instead of a table.")
    var json = false

    func run() throws {
        let displays = TransomKit.Displays.all()
        Log.general.notice("displays: \(displays.count, privacy: .public) display(s)")

        if json {
            print(Self.jsonString(displays))
            return
        }

        print("Displays (\(displays.count)):")
        for d in displays {
            let flag = d.isMain ? " [main]" : ""
            print(
                "  id=\(d.id)\(flag)\n"
                    + "    pixels : \(d.pixelWidth)x\(d.pixelHeight)  "
                    + "origin_px=(\(Int(d.pixelBounds.origin.x)),\(Int(d.pixelBounds.origin.y)))\n"
                    + "    points : \(Int(d.sizePoints.width))x\(Int(d.sizePoints.height))  "
                    + "origin_pt=(\(Int(d.originPoints.x)),\(Int(d.originPoints.y)))\n"
                    + "    scale  : \(String(format: "%.2f", d.scale))x")
        }
    }

    private static func jsonString(_ displays: [DisplayInfo]) -> String {
        let objs = displays.map { d -> String in
            """
            {"id":\(d.id),"main":\(d.isMain),\
            "pixelWidth":\(d.pixelWidth),"pixelHeight":\(d.pixelHeight),\
            "originPxX":\(Int(d.pixelBounds.origin.x)),"originPxY":\(Int(d.pixelBounds.origin.y)),\
            "pointWidth":\(Int(d.sizePoints.width)),"pointHeight":\(Int(d.sizePoints.height)),\
            "originPtX":\(Int(d.originPoints.x)),"originPtY":\(Int(d.originPoints.y)),\
            "scale":\(d.scale)}
            """
        }
        return "[\(objs.joined(separator: ","))]"
    }
}
