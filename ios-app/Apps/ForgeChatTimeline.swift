import Foundation

struct ForgeChatThread: Codable, Identifiable, Equatable {
    let id: UUID; let title: String?; let status: String?; let createdAt: String?; let updatedAt: String?
}
struct ForgeChatArtifact: Codable, Equatable { let id: UUID; let kind: String; let name: String?; let size: Int64?; let sha256: String?; let expiresAt: String? }
struct ForgeChatResult: Codable, Equatable { let inboxID: UUID?; let tweakID: UUID?; let bundleID: String?; let name: String?; let version: Int?; let artifact: ForgeChatArtifact? }
struct ForgeChatMessage: Codable, Identifiable, Equatable {
    let id: UUID; let threadID: UUID; let role: String; let text: String?; let createdAt: String?; let hasImage: Bool?; let result: ForgeChatResult?
    init(id: UUID, threadID: UUID, role: String, text: String?, createdAt: String? = nil, hasImage: Bool? = nil, result: ForgeChatResult? = nil) {
        self.id = id; self.threadID = threadID; self.role = role; self.text = text; self.createdAt = createdAt; self.hasImage = hasImage; self.result = result
    }
    enum K: String, CodingKey { case id, threadID, role, text, createdAt, hasImage, result }
    /// Tolerant on purpose: unknown roles (kat, operator...), missing threadID, odd optional types must never drop a reply.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(UUID.self, forKey: .id)
        threadID = (try? c.decode(UUID.self, forKey: .threadID)) ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        role = (try? c.decode(String.self, forKey: .role)) ?? "kat"
        text = try? c.decode(String.self, forKey: .text)
        createdAt = try? c.decode(String.self, forKey: .createdAt)
        hasImage = try? c.decode(Bool.self, forKey: .hasImage)
        result = try? c.decode(ForgeChatResult.self, forKey: .result)
    }
}

/// A message keeps its UUID until the server accepted it, so retries replay instead of duplicating.
struct ForgeChatOutgoing: Codable, Identifiable, Equatable { let id: UUID; let threadID: UUID; let newThread: Bool; let text: String; var imageBase64: String? }


/// Reads may lag behind accepted sends or arrive out of order. Only explicit thread deletion
/// removes history; polling preserves previously visible IDs and updates matching server rows.
enum ForgeChatTimeline {
    static func acceptedEcho(_ outgoing: ForgeChatOutgoing) -> ForgeChatOutgoing {
        var echo = outgoing
        echo.imageBase64 = nil // never persist the uploaded image twice
        return echo
    }

    static func pending(outgoing: [ForgeChatOutgoing], echoes: [ForgeChatOutgoing],
                        confirmed: [ForgeChatMessage], threadID: UUID) -> [ForgeChatOutgoing] {
        let confirmedIDs = Set(confirmed.map(\.id))
        return mergeConfirmed(previous: echoes, incoming: outgoing).filter {
            $0.threadID == threadID && !confirmedIDs.contains($0.id)
        }
    }

    static func mergeConfirmed<Row: Identifiable & Equatable>(previous: [Row], incoming: [Row]) -> [Row] {
        var rows: [Row] = []
        var positions: [Row.ID: Int] = [:]
        for row in previous + incoming {
            if let position = positions[row.id] {
                rows[position] = row
            } else {
                positions[row.id] = rows.count
                rows.append(row)
            }
        }
        return rows
    }
}
