import Foundation
import CoreFoundation

/// Strict allowlisted, versioned data, never executable CAML, paths or URLs.
struct WallpaperLayoutPlan {
    struct Layer {
        let id: UUID
        let role: WallpaperPhotoLayer.Role
        let zoom: Double
        let x: Double
        let y: Double
        let crop: Bool
    }
    let layers: [Layer]
    let avoidClock: Bool
    enum Invalid: Error { case plan, unavailable }
    static func parse(_ data: Data, knownIDs: [UUID]) throws -> Self {
        guard data.count <= 16384, !knownIDs.isEmpty, knownIDs.count <= 8,
              Set(knownIDs).count == knownIDs.count,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys) == Set(["version", "layers", "parallaxStrength", "clockArea"]),
              let version = number(root["version"]), version == 1,
              let parallax = number(root["parallaxStrength"]), parallax == 0,
              let clock = root["clockArea"] as? String, ["none", "avoidTop"].contains(clock),
              let items = root["layers"] as? [[String: Any]], items.count == knownIDs.count else { throw Invalid.plan }
        var seen = Set<UUID>()
        let result = try items.map { row -> Layer in
            guard Set(row.keys) == Set(["id", "role", "zoom", "x", "y", "crop"]),
                  let rawID = row["id"] as? String, rawID.count == 36,
                  let id = UUID(uuidString: rawID), knownIDs.contains(id), seen.insert(id).inserted,
                  let rawRole = row["role"] as? String, let role = WallpaperPhotoLayer.Role(rawValue: rawRole),
                  let zoom = number(row["zoom"]), (1...4).contains(zoom),
                  let x = number(row["x"]), (-1...1).contains(x),
                  let y = number(row["y"]), (-1...1).contains(y),
                  let crop = row["crop"] as? NSNumber, CFGetTypeID(crop) == CFBooleanGetTypeID() else { throw Invalid.plan }
            return Layer(id: id, role: role, zoom: zoom, x: x, y: y, crop: crop.boolValue)
        }
        return Self(layers: result, avoidClock: clock == "avoidTop")
    }
    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }
    func apply(to photos: [WallpaperPhotoLayer]) throws -> [WallpaperPhotoLayer] {
        guard Set(photos.map(\.id)) == Set(layers.map(\.id)), photos.count == layers.count else { throw Invalid.plan }
        return try layers.map { plan in
            guard var photo = photos.first(where: { $0.id == plan.id }) else { throw Invalid.plan }
            photo.role = plan.role; photo.zoom = plan.zoom; photo.x = plan.x
            photo.y = avoidClock && plan.role == .foreground ? max(0.35, plan.y) : plan.y
            photo.crop = plan.crop
            return photo
        }
    }
}

enum WallpaperLayoutAI {
    /// Build-time gate. Server route is staged only; no production request while off.
    static let enabled = false
    static func request(description: String, layers: [WallpaperPhotoLayer]) async throws -> WallpaperLayoutPlan {
        try await request(description: description, layers: layers, allowed: enabled) { body in
            try await ForgeClient.post(body, timeout: 30)
        }
    }
    static func request(description: String, layers: [WallpaperPhotoLayer], allowed: Bool,
                        transport: ([String: Any]) async throws -> Data) async throws -> WallpaperLayoutPlan {
        guard allowed, !description.isEmpty, description.utf8.count <= 2000,
              !layers.isEmpty, layers.count <= 8 else { throw WallpaperLayoutPlan.Invalid.unavailable }
        let body: [String: Any] = [
            "action": "wallpaper-layout", "version": 1, "description": description,
            "photos": layers.map { ["id": $0.id.uuidString, "width": $0.image.size.width,
                                    "height": $0.image.size.height] as [String: Any] },
            "capabilities": ["parallaxStrength": 0, "segmentation": false]
        ]
        // Only IDs and dimensions leave the device; photo pixels never do.
        return try WallpaperLayoutPlan.parse(await transport(body), knownIDs: layers.map(\.id))
    }
}
