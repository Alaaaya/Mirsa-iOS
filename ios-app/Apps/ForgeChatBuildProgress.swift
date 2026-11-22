import SwiftUI

/// Additive, optional per-user-message build progress snapshot from the backend (field "buildProgress").
/// UI shows it only when requestMessageID equals the user message's own ID. Nothing is simulated or inferred.
/// Contract: docs/chat-build-progress.md
enum ChatBuildPhase: String, Codable, CaseIterable { case understood, building, check, ready, queued
    static let steps: [ChatBuildPhase] = [.understood, .building, .check, .ready] }

struct ChatBuildEvent: Codable, Equatable {
    let phase: ChatBuildPhase; let line: String; let at: String?
}
struct ChatBuildProgress: Codable, Equatable {
    static let maxEvents = 40, maxLineLength = 160
    let requestMessageID: UUID; let buildID: String?; let phase: ChatBuildPhase
    let fraction: Double?; let title: String?; let events: [ChatBuildEvent]
    var failed: Bool = false
    /// True when derived from coarse server lifecycle (queued/working only): no step list, indeterminate.
    var coarse: Bool = false
    enum K: String, CodingKey { case requestMessageID, buildID, phase, fraction, title, events, failed }
    init(requestMessageID: UUID, buildID: String? = nil, phase: ChatBuildPhase, fraction: Double? = nil, title: String? = nil, events: [ChatBuildEvent] = [], failed: Bool = false, coarse: Bool = false) {
        self.coarse = coarse
        self.requestMessageID = requestMessageID; self.buildID = buildID; self.phase = phase
        self.fraction = Self.cleanFraction(fraction); self.title = title; self.events = Self.bounded(events); self.failed = failed
    }
    /// Explicit contract: coarse is local-only and never encoded.
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: K.self)
        try c.encode(requestMessageID, forKey: .requestMessageID)
        try c.encode(phase, forKey: .phase)
        try c.encodeIfPresent(buildID, forKey: .buildID)
        try c.encodeIfPresent(fraction, forKey: .fraction)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encode(events, forKey: .events)
        try c.encode(failed, forKey: .failed)
    }
    /// Throws on unknown phase or missing IDs so the whole snapshot decodes to nil on the message.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        requestMessageID = try c.decode(UUID.self, forKey: .requestMessageID)
        phase = try c.decode(ChatBuildPhase.self, forKey: .phase)
        buildID = try? c.decode(String.self, forKey: .buildID)
        fraction = Self.cleanFraction(try? c.decode(Double.self, forKey: .fraction))
        title = try? c.decode(String.self, forKey: .title)
        struct Lossy: Decodable { let v: ChatBuildEvent?; init(from d: Decoder) throws { v = try? ChatBuildEvent(from: d) } }
        events = Self.bounded(((try? c.decode([Lossy].self, forKey: .events)) ?? []).compactMap(\.v))
        failed = (try? c.decode(Bool.self, forKey: .failed)) ?? false
    }
    /// Out of range or non-finite means unknown (nil), never clamped into a fake value; only float noise is clamped.
    static func cleanFraction(_ f: Double?) -> Double? {
        guard let f, f.isFinite, f >= -0.001, f <= 1.001 else { return nil }
        return min(1, max(0, f))
    }
    static func bounded(_ e: [ChatBuildEvent]) -> [ChatBuildEvent] {
        e.suffix(maxEvents).map { ChatBuildEvent(phase: $0.phase, line: String($0.line.prefix(maxLineLength)), at: $0.at) }
    }
    var isRunning: Bool { !failed && phase != .ready }
    func matches(_ id: UUID) -> Bool { requestMessageID == id }
}

/// Top-level chat-read "lifecycle" row (additive, tolerant). Only exact sourceMessageID binds to a bubble.
struct ChatLifecycleEntry: Decodable, Equatable {
    let id: UUID; let sourceMessageID: UUID?; let kind: String?; let state: String; let version: Int?; let artifactID: UUID?
    enum K: String, CodingKey { case id, sourceMessageID, kind, state, version, artifactID }
    init(id: UUID, sourceMessageID: UUID?, kind: String? = nil, state: String, version: Int? = nil, artifactID: UUID? = nil) {
        self.id = id; self.sourceMessageID = sourceMessageID; self.kind = kind; self.state = state; self.version = version; self.artifactID = artifactID
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(UUID.self, forKey: .id)
        sourceMessageID = (try? c.decode(String.self, forKey: .sourceMessageID)).flatMap { UUID(uuidString: $0) }
        kind = try? c.decode(String.self, forKey: .kind)
        state = (try? c.decode(String.self, forKey: .state)) ?? "unknown"
        version = try? c.decode(Int.self, forKey: .version)
        artifactID = (try? c.decode(String.self, forKey: .artifactID)).flatMap { UUID(uuidString: $0) }
    }
    /// One odd row never drops the others.
    static func lossy(_ data: Data) -> [ChatLifecycleEntry] {
        struct L: Decodable { let v: ChatLifecycleEntry?; init(from d: Decoder) throws { v = try? ChatLifecycleEntry(from: d) } }
        struct W: Decodable { let lifecycle: [L]? }
        return ((try? JSONDecoder().decode(W.self, from: data))?.lifecycle ?? []).compactMap(\.v)
    }
}

enum ChatBuildStyle: String, CaseIterable {
    case terminal, pill
    static let key = "mirsa.chat.buildProgressStyle"
    static func resolve(_ raw: String) -> ChatBuildStyle { ChatBuildStyle(rawValue: raw) ?? .terminal }
}

/// Pure placement rules used by ForgeChat: exactly one style at a time, exact-ID match only.
enum ChatBuildPresentation {
    /// Explicit events snapshot wins; else honest coarse lifecycle (queued/working) bound by exact sourceMessageID.
    static func resolve(message m: ForgeChatMessage, lifecycle: [ChatLifecycleEntry], messages: [ForgeChatMessage]) -> ChatBuildProgress? {
        guard m.role == "user" else { return nil }
        if let p = m.buildProgress, p.matches(m.id) {
            // A ready snapshot is never trusted without a real delivered artifact.
            if p.phase == .ready, !p.failed {
                guard let e = lifecycle.last(where: { $0.sourceMessageID == m.id }), let a = e.artifactID,
                      messages.contains(where: { $0.result?.artifact?.id == a }) else { return nil }
            }
            return p
        }
        guard let e = lifecycle.last(where: { $0.sourceMessageID == m.id }) else { return nil }
        switch e.state {
        case "queued": return ChatBuildProgress(requestMessageID: m.id, buildID: e.id.uuidString, phase: .queued, coarse: true)
        case "working": return ChatBuildProgress(requestMessageID: m.id, buildID: e.id.uuidString, phase: .building, coarse: true)
        case "ready":
            // Ready only with a real delivered artifact that matches the lifecycle row.
            guard let a = e.artifactID, messages.contains(where: { $0.result?.artifact?.id == a }) else { return nil }
            return ChatBuildProgress(requestMessageID: m.id, buildID: e.id.uuidString, phase: .ready, coarse: true)
        default: return nil
        }
    }
    static func card(style: ChatBuildStyle, message: ForgeChatMessage?, lifecycle: [ChatLifecycleEntry], messages: [ForgeChatMessage]) -> ChatBuildProgress? {
        guard style == .terminal, let m = message else { return nil }
        return resolve(message: m, lifecycle: lifecycle, messages: messages)
    }
    /// Newest running snapshot for the header pill (pill style only).
    static func pill(style: ChatBuildStyle, messages: [ForgeChatMessage], lifecycle: [ChatLifecycleEntry]) -> ChatBuildProgress? {
        guard style == .pill else { return nil }
        return messages.reversed().lazy.compactMap { resolve(message: $0, lifecycle: lifecycle, messages: messages) }.first(where: \.isRunning)
    }
}

enum ChatBuildText {
    static var terminalTitle: String { tr5("Terminal card", "بطاقة ترمينال", de: "Terminal-Karte", ckb: "کارتی تێرمیناڵ", kmr: "Karta terminal") }
    static var pillTitle: String { tr5("Top pill", "شريط علوي", de: "Pille oben", ckb: "پیلی سەرەوە", kmr: "Pilla jorîn") }
    static var settingTitle: String { tr5("Build progress", "تقدم البناء", de: "Build-Fortschritt", ckb: "پێشکەوتنی دروستکردن", kmr: "Pêşketina çêkirinê") }
    static func phase(_ p: ChatBuildPhase) -> String {
        switch p {
        case .understood: return tr5("Understood", "مفهوم", de: "Verstanden", ckb: "تێگەیشتم", kmr: "Têgihîştim")
        case .building: return tr5("Building", "عم ينبني", de: "Wird gebaut", ckb: "دروست دەکرێت", kmr: "Tê çêkirin")
        case .queued: return tr5("In queue", "بالدور", de: "In Warteschlange", ckb: "لە ڕیزدایە", kmr: "Di rêzê de")
        case .check: return tr5("Checking", "فحص", de: "Prüfung", ckb: "پشکنین", kmr: "Kontrol")
        case .ready: return tr5("Ready", "جاهز", de: "Fertig", ckb: "ئامادەیە", kmr: "Amade")
        }
    }
    static var failed: String { tr5("Stopped", "توقف", de: "Gestoppt", ckb: "وەستا", kmr: "Sekinî") }
    static var rtl: Bool { L.lang == .arabic || L.lang == .sorani }
}

extension ChatBuildPhase { var index: Int { Self.steps.firstIndex(of: self) ?? -1 } }

/// Terminal card: black glass, monospace, bounded backend lines, step row, blinking cursor (static under Reduce Motion).
struct ChatBuildTerminalCard: View {
    let progress: ChatBuildProgress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(progress.coarse ? [progress.phase] : ChatBuildPhase.steps, id: \.self) { p in
                    let done = !progress.coarse && p.index < progress.phase.index
                    let current = progress.coarse || p.index == progress.phase.index
                    HStack(spacing: 3) {
                        if current && progress.isRunning { ProgressView().controlSize(.mini).tint(.cyan) } else { Image(systemName: done || current ? "checkmark.circle.fill" : "circle").font(.system(size: 10)) }
                        Text(ChatBuildText.phase(p)).font(.system(size: 10, weight: .medium))
                    }.foregroundStyle(done ? Color.green : (current ? Color.cyan : Color.white.opacity(0.4)))
                }
                Spacer(minLength: 0)
                if let f = progress.fraction { Text("\(Int((f * 100).rounded()))%").font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.7)) }
            }
            ForEach(Array(progress.events.suffix(8).enumerated()), id: \.offset) { _, e in
                Text("> " + e.line).font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
            }
            if progress.isRunning { cursor }
            if progress.failed { Text(ChatBuildText.failed).font(.system(size: 11, design: .monospaced)).foregroundStyle(.orange) }
        }
        .environment(\.layoutDirection, ChatBuildText.rtl ? .rightToLeft : .leftToRight)
        .padding(12).frame(maxWidth: 320, alignment: ChatBuildText.rtl ? .trailing : .leading)
        .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(LinearGradient(colors: [Color.purple.opacity(0.55), Color.cyan.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ChatBuildText.phase(progress.phase))
        .accessibilityIdentifier("chat-build-terminal")
    }
    private var cursor: some View {
        TimelineView(.periodic(from: .now, by: 0.55)) { t in
            let on = reduceMotion || scenePhase != .active || Int(t.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0
            Text("▍").font(.system(size: 11, design: .monospaced)).foregroundStyle(.green).opacity(on ? 1 : 0)
        }
    }
}

/// Live Activity-style pill for the header inset. Real phase; real fraction only when provided.
struct ChatBuildPill: View {
    let progress: ChatBuildProgress
    var body: some View {
        HStack(spacing: 8) {
            if let ic = MirsaAppIconImage.image { Image(uiImage: ic).resizable().frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous)) } else { Image(systemName: "hammer.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white) }
            VStack(alignment: .leading, spacing: 3) {
                Text(progress.title ?? ChatBuildText.phase(progress.phase)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                if progress.coarse && progress.isRunning { ProgressView().controlSize(.mini).tint(.white) }
                else if let f = progress.fraction { ProgressView(value: f).tint(.white).frame(width: 90) }
                else { Text(ChatBuildText.phase(progress.phase)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.7)) }
            }
        }
        .environment(\.layoutDirection, ChatBuildText.rtl ? .rightToLeft : .leftToRight)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.black, in: Capsule())
        .overlay(Capsule().stroke(LinearGradient(colors: [Color.purple.opacity(0.6), Color.cyan.opacity(0.5)], startPoint: .leading, endPoint: .trailing), lineWidth: 0.8))
        .accessibilityElement(children: .combine).accessibilityIdentifier("chat-build-pill")
    }
}

#if DEBUG
/// SYNTHETIC TEST-ONLY fixture. Never reachable from production data flow.
enum ChatBuildProgressTestFixture {
    static func sample(for id: UUID) -> ChatBuildProgress {
        ChatBuildProgress(requestMessageID: id, buildID: "SYNTHETIC-TEST", phase: .building, fraction: 0.5, title: "SYNTHETIC TEST",
                          events: [ChatBuildEvent(phase: .understood, line: "SYNTHETIC TEST understood", at: nil), ChatBuildEvent(phase: .building, line: "SYNTHETIC TEST building", at: nil)])
    }
}
#endif
