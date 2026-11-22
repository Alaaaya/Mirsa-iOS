#if DEBUG
import UIKit

/// Original procedural art, confined to an explicitly launched UI-test harness.
/// Nothing here is a downloadable archive or third-party wallpaper.
enum WallpaperSourceFixture {
    static var active: Bool {
        MirsaUITestHarness.active &&
        ProcessInfo.processInfo.arguments.contains("-MirsaWallpaperSourceFixture")
    }

    static var feed: WallpaperSourceFeed {
        WallpaperSourceFeed(name: "Mirsa Originals", author: "Mirsa · UI test fixture",
            wallpapers: (0..<6).map { index in
                WallpaperSourceEntry(id: "original-\(index)",
                    name: ["Solar arc", "Night tide", "Cinder", "Dune", "Lagoon", "Halo"][index],
                    author: "Mirsa",
                    previewImage: URL(string: "https://wallpaper-fixture.invalid/\(index).png")!,
                    previewVideo: index == 0 ? URL(string: "https://wallpaper-fixture.invalid/preview.mp4")! : nil,
                    url: URL(string: "https://wallpaper-fixture.invalid/\(index).tendies")!,
                    size: Int64(1_048_576 + index * 65_536),
                    category: "Original procedural art")
            })
    }

    static func image(for entry: WallpaperSourceEntry) -> UIImage? {
        guard active, let index = Int(entry.id.replacingOccurrences(of: "original-", with: "")),
              (0..<6).contains(index) else { return nil }
        let palettes: [(UIColor, UIColor)] = [
            (.init(red: 0.05, green: 0.09, blue: 0.15, alpha: 1), .init(red: 1, green: 0.53, blue: 0.23, alpha: 1)),
            (.init(red: 0.01, green: 0.12, blue: 0.18, alpha: 1), .init(red: 0.18, green: 0.85, blue: 0.75, alpha: 1)),
            (.init(red: 0.15, green: 0.02, blue: 0.04, alpha: 1), .init(red: 0.98, green: 0.25, blue: 0.18, alpha: 1)),
            (.init(red: 0.2, green: 0.12, blue: 0.07, alpha: 1), .init(red: 0.94, green: 0.77, blue: 0.48, alpha: 1)),
            (.init(red: 0.02, green: 0.11, blue: 0.09, alpha: 1), .init(red: 0.47, green: 0.9, blue: 0.65, alpha: 1)),
            (.init(red: 0.08, green: 0.07, blue: 0.2, alpha: 1), .init(red: 0.65, green: 0.72, blue: 1, alpha: 1))
        ]
        let palette = palettes[index]
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 420, height: 720), format: format).image { context in
            palette.0.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 420, height: 720))
            for ring in stride(from: 14, through: 0, by: -1) {
                palette.1.withAlphaComponent(CGFloat(15 - ring) / 25).setStroke()
                let radius = CGFloat(48 + ring * 20)
                let arc = UIBezierPath(ovalIn: CGRect(x: 280 - radius, y: 280 - radius,
                                                      width: radius * 2, height: radius * 2))
                arc.lineWidth = 9
                arc.stroke()
            }
            palette.0.setFill()
            context.fill(CGRect(x: 0, y: 490, width: 420, height: 230))
            palette.1.withAlphaComponent(0.5).setFill()
            let horizon = UIBezierPath()
            horizon.move(to: CGPoint(x: 0, y: 560))
            horizon.addCurve(to: CGPoint(x: 420, y: 600), controlPoint1: CGPoint(x: 140, y: 400),
                             controlPoint2: CGPoint(x: 290, y: 730))
            horizon.addLine(to: CGPoint(x: 420, y: 720))
            horizon.addLine(to: CGPoint(x: 0, y: 720))
            horizon.close()
            horizon.fill()
        }
    }
}
#endif
