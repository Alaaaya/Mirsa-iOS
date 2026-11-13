import Foundation

struct ForgeChatThread: Codable, Identifiable, Equatable {
    let id: UUID; let title: String?; let status: String?; let createdAt: String?; let updatedAt: String?
}
struct ForgeChatArtifact: Codable, Equatable { let id: UUID; let kind: String; let name: String?; let size: Int64?; let sha256: String?; let expiresAt: String? }
struct ForgeChatResult: Codable, Equatable { let inboxID: UUID?; let tweakID: UUID?; let bundleID: String?; let name: String?; let version: Int?; let artifact: ForgeChatArtifact? }
/// Public attachment metadata (Mirsa 2.1 attachments contract): returned by chat-attachment-put,
/// in chat-send's message.attachments and in chat-read messages. Expired rows come back with
/// available:false and no bytes. Never carries file contents.
struct ChatAttachmentMeta: Codable, Identifiable, Equatable, Hashable {
    let id: UUID; let kind: String; let name: String?; let mime: String?; let size: Int64?
    let sha256: String?; let expiresAt: String?; let available: Bool; let url: String?
    init(id: UUID, kind: String, name: String?, mime: String? = nil, size: Int64? = nil, sha256: String? = nil,
         expiresAt: String? = nil, available: Bool = true, url: String? = nil) {
        self.id = id; self.kind = kind; self.name = name; self.mime = mime; self.size = size
        self.sha256 = sha256; self.expiresAt = expiresAt; self.available = available; self.url = url
    }
    enum CodingKeys: String, CodingKey { case id, kind, name, mime, size, sha256, expiresAt, available, url }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "file"
        name = try? c.decode(String.self, forKey: .name)
        mime = try? c.decode(String.self, forKey: .mime)
        size = try? c.decode(Int64.self, forKey: .size)
        sha256 = try? c.decode(String.self, forKey: .sha256)
        expiresAt = try? c.decode(String.self, forKey: .expiresAt)
        available = (try? c.decode(Bool.self, forKey: .available)) ?? true
        url = try? c.decode(String.self, forKey: .url)
    }
    /// Locally known to be past its absolute 24 h TTL (or marked unavailable by the server).
    func isExpired(now: Date = Date()) -> Bool {
        if !available { return true }
        guard let e = expiresAt else { return false }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let g = ISO8601DateFormatter(); g.formatOptions = [.withInternetDateTime]
        guard let date = f.date(from: e) ?? g.date(from: e) else { return false }
        return date <= now
    }
}

struct ForgeChatMessage: Codable, Identifiable, Equatable {
    let id: UUID; let threadID: UUID; let role: String; let text: String?; let createdAt: String?; let hasImage: Bool?; let result: ForgeChatResult?
    /// Mirsa 2.1: message.attachments (public metadata only). nil for every pre-2.1 message.
    let attachments: [ChatAttachmentMeta]?
    init(id: UUID, threadID: UUID, role: String, text: String?, createdAt: String? = nil, hasImage: Bool? = nil, result: ForgeChatResult? = nil, attachments: [ChatAttachmentMeta]? = nil) {
        self.id = id; self.threadID = threadID; self.role = role; self.text = text; self.createdAt = createdAt; self.hasImage = hasImage; self.result = result; self.attachments = attachments
    }
    enum K: String, CodingKey { case id, threadID, role, text, createdAt, hasImage, result, attachments }
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
        // One odd attachment row must never hide the message or its other attachments.
        struct Lossy: Decodable { let value: ChatAttachmentMeta?; init(from d: Decoder) throws { value = try? ChatAttachmentMeta(from: d) } }
        let rows = (try? c.decode([Lossy].self, forKey: .attachments))?.compactMap(\.value)
        attachments = (rows?.isEmpty ?? true) ? nil : rows
    }
}

/// A message keeps its UUID until the server accepted it, so retries replay instead of duplicating.
struct ForgeChatOutgoing: Codable, Identifiable, Equatable {
    let id: UUID; let threadID: UUID; let newThread: Bool; let text: String; var imageBase64: String?
    /// Last visible row when sending, not a device-clock guess. Optional for saved v1 drafts.
    let afterMessageID: UUID?
    /// Mirsa 2.1: server attachment IDs bound to this message (max 3, unique). Kept with the
    /// message UUID across network retries. Never sent together with the legacy imageBase64.
    var attachmentIDs: [UUID]?
    init(id: UUID, threadID: UUID, newThread: Bool, text: String, imageBase64: String?, afterMessageID: UUID? = nil, attachmentIDs: [UUID]? = nil) {
        self.id = id; self.threadID = threadID; self.newThread = newThread
        self.text = text; self.imageBase64 = imageBase64; self.afterMessageID = afterMessageID
        self.attachmentIDs = attachmentIDs
    }
}


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

    /// Server reads are in causal order. Reorder only their known IDs, retaining any
    /// rows absent from a lagging/partial read in their existing slots.
    static func mergeConfirmed(previous: [ForgeChatMessage], incoming: [ForgeChatMessage]) -> [ForgeChatMessage] {
        let merged = mergeRows(previous: previous, incoming: incoming)
        let canonical = mergeRows(previous: [ForgeChatMessage](), incoming: incoming)
        let incomingIDs = Set(canonical.map(\.id))
        var index = 0
        return merged.map { row in
            guard incomingIDs.contains(row.id) else { return row }
            defer { index += 1 }
            return canonical[index]
        }
    }

    /// Insert optimistic sends at the point the user sent them, before a later
    /// assistant reply even if a poll has not returned the matching user row yet.
    static func orderedIDs(confirmed: [ForgeChatMessage], pending: [ForgeChatOutgoing]) -> [UUID] {
        var ids = confirmed.map(\.id)
        var tails: [UUID: UUID] = [:]
        var headTail: UUID?
        for row in pending where !ids.contains(row.id) {
            if let anchor = row.afterMessageID, let position = ids.firstIndex(of: tails[anchor] ?? anchor) {
                ids.insert(row.id, at: position + 1)
                tails[anchor] = row.id
            } else if row.afterMessageID == nil {
                let position = headTail.flatMap { ids.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
                ids.insert(row.id, at: position)
                headTail = row.id
            } else {
                // Unknown anchor from old/partial history: keep the draft visible.
                ids.append(row.id)
            }
        }
        return ids
    }

    static func mergeConfirmed<Row: Identifiable & Equatable>(previous: [Row], incoming: [Row]) -> [Row] {
        mergeRows(previous: previous, incoming: incoming)
    }

    private static func mergeRows<Row: Identifiable & Equatable>(previous: [Row], incoming: [Row]) -> [Row] {
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
