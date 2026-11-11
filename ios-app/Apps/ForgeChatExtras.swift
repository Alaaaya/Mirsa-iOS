import SwiftUI
import UIKit

// Mirsa 2.2 chat extras: swipe-to-reply with quote, iMessage-style long-press menu with reactions,
// edit / delete for the user's own messages, and unread badges. Aurora look, LTR, 4 languages.

/// Server-side parts are proposals for Kat and stay OFF until Kat confirms the contract.
/// Off: quotes and reactions live on this device only; Edit/Delete are hidden (they need the server).
enum ForgeChatFeatures {
    /// chat-send `replyToMessageID` + chat-react. PROPOSED, not confirmed by Kat.
    static let serverReplyAndReactions = false
    /// chat-edit + chat-delete-message. PROPOSED, not confirmed by Kat.
    static let serverEditDelete = false
}

enum ForgeChatExtrasText {
    static var copy: String { tr("Copy", "نسخ", ckb: "کۆپی", kmr: "Kopî bike") }
    static var reply: String { tr("Reply", "رد", ckb: "وەڵام", kmr: "Bersiv") }
    static var edit: String { tr("Edit", "تعديل", ckb: "دەستکاری", kmr: "Biguherîne") }
    static var delete: String { tr("Delete", "حذف", ckb: "سڕینەوە", kmr: "Jê bibe") }
    static var deleteTitle: String { tr("Delete this message?", "حذف هالرسالة؟", ckb: "ئەم نامەیە بسڕیتەوە؟", kmr: "Ev peyam were jêbirin?") }
    static var replyToMirsa: String { tr("Replying to Mirsa AI", "رد على مرسى AI", ckb: "وەڵامدانەوەی مرسا AI", kmr: "Bersiva Mirsa AI") }
    static var replyToYou: String { tr("Replying to yourself", "رد على رسالتك", ckb: "وەڵامدانەوەی نامەکەت", kmr: "Bersiva peyama te") }
    static var editing: String { tr("Editing message", "عم تعدّل الرسالة", ckb: "دەستکاریکردنی نامە", kmr: "Peyam tê guhertin") }
    static var editFailed: String { tr("Couldn't edit. Mirsa may have already started on it.", "ما زبط التعديل، يمكن مرسى بلّش يشتغل عليه.", ckb: "دەستکاری نەکرا، لەوانەیە مرسا دەستی پێکردبێت.", kmr: "Nehat guhertin, dibe ku Mirsa dest pê kiribe.") }
    static var deleteFailed: String { tr("Couldn't delete the message. Try again.", "ما زبط حذف الرسالة. جرّب مرة تانية.", ckb: "نامەکە نەسڕایەوە. دووبارە هەوڵبدەرەوە.", kmr: "Peyam jê neçû. Dîsa biceribîne.") }
    static var originalGone: String { tr("Original message unavailable", "الرسالة الأصلية مو موجودة", ckb: "نامە ڕەسەنەکە بەردەست نییە", kmr: "Peyama eslî tune ye") }
    static var attachment: String { tr("Attachment", "مرفق", ckb: "هاوپێچ", kmr: "Pêvek") }
    static func unread(_ n: Int) -> String { tr("\(n) new", "\(n) جديد", ckb: "\(n) نوێ", kmr: "\(n) nû") }
    static var selectText: String { tr("Select Text", "تحديد النص", ckb: "دیاریکردنی دەق", kmr: "Nivîsê hilbijêre") }
    static var done: String { tr("Done", "تم", ckb: "تەواو", kmr: "Temam") }
    /// Mirsa 2.3: one-time tip on the first long press of a Mirsa AI reply, also shown in Settings › Mirsa AI.
    static var reactionsHint: String { tr("Press and hold to react, copy or reply. 👎 sends the reply for review so we know what went wrong, and nobody but us sees it.", "اضغط مطوّل لتتفاعل أو تنسخ أو ترد. 👎 بيبعت الرد للمراجعة لنعرف شو كان غلط، وما حدا غيرنا بيشوفو.", ckb: "پەنجە ڕاگرە بۆ کاردانەوە، کۆپیکردن یان وەڵامدانەوە. 👎 وەڵامەکە دەنێرێت بۆ پێداچوونەوە تا بزانین چی هەڵە بوو، و جگە لە ئێمە کەس نایبینێت.", kmr: "Ji bo bertek, kopîkirin an bersivdanê bi dirêjî bitikîne. 👎 bersivê ji bo vekolînê dişîne da ku em bizanin çi xelet bû, û ji bilî me kes wê nabîne.") }
    static var reactionsHintTitle: String { tr("Reactions", "التفاعلات", ckb: "کاردانەوەکان", kmr: "Bertek") }
    static var newMessages: String { tr("New messages", "رسائل جديدة", ckb: "نامەی نوێ", kmr: "Peyamên nû") }
}

struct ForgeChatReplyRef: Codable, Equatable { let messageID: UUID; let snippet: String; let fromUser: Bool }

/// Device-local chat state: quotes, reactions, last-seen marks for unread badges.
@MainActor final class ForgeChatLocal: ObservableObject {
    static let shared = ForgeChatLocal()
    static let reactions = ["👍", "❤️", "👎", "😭", "❓", "😂", "🔥", "🙏"]
    @Published private(set) var replies: [UUID: ForgeChatReplyRef] = [:]
    @Published private(set) var reactions: [UUID: String] = [:]
    @Published private(set) var seen: [UUID: String] = [:]
    private let repliesKey = "mirsa.chat.replies.v1", reactionsKey = "mirsa.chat.reactions.v1", seenKey = "mirsa.chat.seen.v1"
    static let usedKey = "mirsa.chat.everUsed"
    // No background polling for badges: they update only from reads the chat already makes while it is on screen and the app is active.
    private var hasBaseline: Bool

    init() {
        let d = UserDefaults.standard
        func load<T: Decodable>(_ k: String) -> T? { d.data(forKey: k).flatMap { try? JSONDecoder().decode(T.self, from: $0) } }
        replies = load(repliesKey) ?? [:]
        reactions = load(reactionsKey) ?? [:]
        seen = load(seenKey) ?? [:]
        hasBaseline = d.data(forKey: seenKey) != nil
    }
    private func save<T: Encodable>(_ v: T, _ k: String) { UserDefaults.standard.set(try? JSONEncoder().encode(v), forKey: k) }

    static func snippet(_ text: String?) -> String {
        let line = (text ?? "").split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return line.isEmpty ? "📎 " + ForgeChatExtrasText.attachment : String(line.prefix(140))
    }
    func setReply(_ ref: ForgeChatReplyRef, for messageID: UUID) { replies[messageID] = ref; save(replies, repliesKey) }
    func toggleReaction(_ emoji: String, on messageID: UUID) {
        if reactions[messageID] == emoji { reactions[messageID] = nil } else { reactions[messageID] = emoji }
        save(reactions, reactionsKey)
    }
    func forget(_ messageID: UUID) {
        replies[messageID] = nil; reactions[messageID] = nil
        save(replies, repliesKey); save(reactions, reactionsKey)
    }

    // MARK: unread
    /// First list ever seen on this device counts as read, so an update never floods old threads with badges.
    func baselineIfNeeded(_ threads: [ForgeChatThread]) {
        guard !hasBaseline, !threads.isEmpty else { return }
        for t in threads { seen[t.id] = t.updatedAt ?? "" }
        hasBaseline = true; save(seen, seenKey)
    }
    func markSeen(_ id: UUID, updatedAt: String?) {
        guard seen[id] != (updatedAt ?? "") else { return }
        seen[id] = updatedAt ?? ""; hasBaseline = true; save(seen, seenKey)
    }
    func isUnread(_ t: ForgeChatThread) -> Bool {
        guard hasBaseline, let u = t.updatedAt, !u.isEmpty else { return false }
        guard let s = seen[t.id] else { return true } // a thread that appeared after the baseline
        return s != u
    }
    func unreadCount(_ threads: [ForgeChatThread]) -> Int { threads.filter(isUnread).count }
}

extension ForgeChatStore {
    enum MessageActionResult: Equatable { case ok, conflict, gone, invalid, unavailable }

    /// Same endpoint, headers and retry rules as chat-report: 401 refresh once, 403 rebind once.
    private func precise(_ body: [String: Any]) async -> (Int, Data?) {
        var refreshed = false, rebound = false
        while true {
            let r: ForgePreciseClient.Response
            do { r = try await ForgePreciseClient.request(body, credentials: try await ForgeClient.fixToken(forceRefresh: refreshed)) }
            catch { lastDiagnostic = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription; return (0, nil) }
            switch r.status {
            case 401 where !refreshed: refreshed = true; continue
            case 403 where !rebound: rebound = true; _ = try? await ForgeClient.get(["action": "gallery"]); continue
            default: return (r.status, r.data)
            }
        }
    }
    private static func map(_ status: Int) -> MessageActionResult {
        switch status { case 200: return .ok; case 409: return .conflict; case 404: return .gone; case 422: return .invalid; default: return .unavailable }
    }

    /// PROPOSED chat-edit {threadID, messageID, text}. Only reachable when ForgeChatFeatures.serverEditDelete.
    func editMessage(threadID: UUID, messageID: UUID, text: String) async -> MessageActionResult {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, ForgeChatText.messageCount(t) <= ForgeChatText.messageMax else { return .invalid }
        if Self.fixture { replaceText(threadID: threadID, messageID: messageID, text: t); return .ok }
        let (status, _) = await precise(["action": "chat-edit", "threadID": threadID.uuidString.lowercased(), "messageID": messageID.uuidString.lowercased(), "text": t])
        if status == 200 { replaceText(threadID: threadID, messageID: messageID, text: t) }
        return Self.map(status)
    }
    private func replaceText(threadID: UUID, messageID: UUID, text: String) {
        guard var list = messages[threadID], let i = list.firstIndex(where: { $0.id == messageID }) else { return }
        let m = list[i]
        list[i] = ForgeChatMessage(id: m.id, threadID: m.threadID, role: m.role, text: text, createdAt: m.createdAt, hasImage: m.hasImage, result: m.result, attachments: m.attachments)
        var all = messages; all[threadID] = list; messages = all
    }

    /// PROPOSED chat-delete-message {threadID, messageID}. Local copy goes only after the server confirms.
    func deleteMessage(threadID: UUID, messageID: UUID) async -> MessageActionResult {
        var status = 200
        if !Self.fixture {
            status = await precise(["action": "chat-delete-message", "threadID": threadID.uuidString.lowercased(), "messageID": messageID.uuidString.lowercased()]).0
        }
        if status == 200 || status == 404 {
            var all = messages; all[threadID]?.removeAll { $0.id == messageID }; messages = all
            ForgeChatLocal.shared.forget(messageID)
        }
        return status == 404 ? .ok : Self.map(status)
    }

    /// PROPOSED chat-react {threadID, messageID, reaction|null}. Fire and forget; the local reaction is the source on this device.
    func sendReaction(threadID: UUID, messageID: UUID, reaction: String?) {
        guard ForgeChatFeatures.serverReplyAndReactions, !Self.fixture else { return }
        Task { _ = await precise(["action": "chat-react", "threadID": threadID.uuidString.lowercased(), "messageID": messageID.uuidString.lowercased(), "reaction": reaction ?? NSNull()]) }
    }
}

// MARK: - Views

/// Quote above a sent message; tap jumps to the original.
struct ForgeChatQuote: View {
    let ref: ForgeChatReplyRef
    let exists: Bool
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(ref.fromUser ? AnyShapeStyle(MirsaPalette.accentGradient) : AnyShapeStyle(MirsaChatTheme.blue)).frame(width: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ref.fromUser ? ForgeChatExtrasText.replyToYou : ForgeChatExtrasText.replyToMirsa).font(.system(size: 11, weight: .semibold)).foregroundStyle(MirsaChatTheme.muted)
                    Text(exists ? ref.snippet : ForgeChatExtrasText.originalGone).font(.system(size: 13)).foregroundStyle(.white.opacity(exists ? 0.85 : 0.5)).lineLimit(1)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: 260, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(!exists)
        .accessibilityIdentifier("chat-quote")
    }
}

/// Bar above the composer: who is quoted, the first line, and ✕ — also used for "Editing message".
struct ForgeChatComposerContext: View {
    let title: String
    let line: String
    let icon: String
    let onCancel: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(MirsaChatTheme.blue)
            RoundedRectangle(cornerRadius: 2).fill(MirsaPalette.accentGradient).frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(MirsaChatTheme.muted)
                Text(line).font(.system(size: 14)).foregroundStyle(.white).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onCancel) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                    .frame(width: 28, height: 28).background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(ForgeChatText.cancel).accessibilityIdentifier("chat-context-cancel")
        }
        .padding(.horizontal, 18).padding(.top, 8)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityIdentifier("chat-composer-context")
    }
}

struct ForgeChatReactionChip: View {
    let emoji: String
    var body: some View {
        Text(emoji).font(.system(size: 15))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 0.5))
            .accessibilityIdentifier("chat-reaction")
    }
}

/// Swipe a message to the right to reply, with a light haptic once the swipe is far enough.
struct ForgeChatSwipeToReply: ViewModifier {
    let enabled: Bool
    let onReply: () -> Void
    @State private var dx: CGFloat = 0
    @State private var armed = false
    func body(content: Content) -> some View {
        content
            .offset(x: dx)
            .overlay(alignment: .leading) {
                if dx > 4 {
                    Image(systemName: "arrowshape.turn.up.left.fill").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white).frame(width: 30, height: 30)
                        .background(Circle().fill(.white.opacity(armed ? 0.25 : 0.1)))
                        .scaleEffect(armed ? 1.1 : 0.85).opacity(Double(min(1, dx / 50)))
                        .offset(x: dx - 36)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 16)
                    .onChanged { v in
                        guard enabled, v.translation.width > 0, abs(v.translation.width) > abs(v.translation.height) * 1.6 else { return }
                        dx = min(84, v.translation.width * 0.65)
                        if dx >= 56, !armed { armed = true; UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                        else if dx < 56, armed { armed = false }
                    }
                    .onEnded { _ in
                        if armed { onReply() }
                        armed = false
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dx = 0 }
                    }
            )
    }
}

/// Long press that opens the menu while the finger is still down (iMessage-style), not on release.
/// A timer starts on touch-down and is cancelled if the finger lifts or moves away (scroll or swipe).
struct ForgeChatHoldToMenu: ViewModifier {
    var duration: Double = 0.35
    let action: () -> Void
    @State private var pending: DispatchWorkItem?
    func body(content: Content) -> some View {
        content.onLongPressGesture(minimumDuration: duration, maximumDistance: 10, perform: {}, onPressingChanged: { pressing in
            pending?.cancel(); pending = nil
            guard pressing else { return }
            let work = DispatchWorkItem { action() }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        })
    }
}

struct ForgeChatMenuTarget: Identifiable, Equatable {
    let id: UUID
    let threadID: UUID
    let text: String
    let isUser: Bool
    let canEdit: Bool
    let canDelete: Bool
    let reactable: Bool
}

/// iMessage-style long-press overlay: reaction row, the message, then Copy / Reply (/ Edit / Delete).
struct ForgeChatMessageMenu: View {
    let target: ForgeChatMenuTarget
    let current: String?
    let onReact: (String) -> Void
    let onCopy: () -> Void
    let onReply: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onClose: () -> Void
    var showHint: Bool = false
    @State private var shown = false
    @State private var selecting = false

    /// Mirsa surface for the menu pieces: raised card colour with a faint violet-to-blue edge.
    private var edge: LinearGradient {
        LinearGradient(colors: [MirsaPalette.accent.opacity(0.55), MirsaPalette.accent2.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).overlay(MirsaPalette.sheet.opacity(0.55)).ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .accessibilityAddTraits(.isButton).accessibilityLabel(ForgeChatText.close)
            VStack(alignment: target.isUser ? .trailing : .leading, spacing: 10) {
                if showHint {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "hand.tap").foregroundStyle(MirsaPalette.accentGradient)
                        Text(ForgeChatExtrasText.reactionsHint).font(.footnote).foregroundStyle(.white.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9).frame(maxWidth: 300, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MirsaPalette.cardRaised))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(edge, lineWidth: 0.8))
                    .opacity(shown ? 1 : 0)
                    .accessibilityIdentifier("chat-reactions-hint")
                }
                if target.reactable {
                    HStack(spacing: 4) {
                        ForEach(ForgeChatLocal.reactions, id: \.self) { e in
                            Button { onReact(e) } label: {
                                Text(e).font(.system(size: 26)).frame(width: 38, height: 38)
                                    .background(Circle().fill(current == e ? AnyShapeStyle(MirsaPalette.accentGradient) : AnyShapeStyle(Color.clear)))
                            }.buttonStyle(.plain).accessibilityIdentifier("chat-react-\(e)")
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Capsule().fill(MirsaPalette.cardRaised))
                    .overlay(Capsule().stroke(edge, lineWidth: 0.8))
                    .shadow(color: MirsaPalette.accent.opacity(0.25), radius: 14, y: 4)
                    .scaleEffect(shown ? 1 : 0.6, anchor: target.isUser ? .bottomTrailing : .bottomLeading).opacity(shown ? 1 : 0)
                    .accessibilityIdentifier("chat-reaction-bar")
                }
                Text(target.text.isEmpty ? "📎" : target.text).font(.system(size: 16)).foregroundStyle(.white).lineLimit(8)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background {
                        if target.isUser { RoundedRectangle(cornerRadius: 22, style: .continuous).fill(MirsaPalette.accentGradient) }
                        else { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(MirsaChatTheme.bubble) }
                    }
                    .frame(maxWidth: 300, alignment: target.isUser ? .trailing : .leading)
                VStack(spacing: 0) {
                    row(ForgeChatExtrasText.reply, "arrowshape.turn.up.left", id: "chat-menu-reply", action: onReply)
                    Divider().overlay(MirsaPalette.stroke)
                    row(ForgeChatExtrasText.copy, "doc.on.doc", id: "chat-menu-copy", action: onCopy)
                    if !target.text.isEmpty {
                        Divider().overlay(MirsaPalette.stroke)
                        row(ForgeChatExtrasText.selectText, "selection.pin.in.out", id: "chat-menu-select") { selecting = true }
                    }
                    if target.canEdit {
                        Divider().overlay(MirsaPalette.stroke)
                        row(ForgeChatExtrasText.edit, "pencil", id: "chat-menu-edit", action: onEdit)
                    }
                    if target.canDelete {
                        Divider().overlay(MirsaPalette.stroke)
                        row(ForgeChatExtrasText.delete, "trash", id: "chat-menu-delete", destructive: true, action: onDelete)
                    }
                }
                .frame(width: 230)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MirsaPalette.cardRaised))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(edge, lineWidth: 0.8))
                .shadow(color: MirsaPalette.accent.opacity(0.22), radius: 16, y: 6)
                .scaleEffect(shown ? 1 : 0.8, anchor: target.isUser ? .topTrailing : .topLeading).opacity(shown ? 1 : 0)
            }
            .frame(maxWidth: .infinity, alignment: target.isUser ? .trailing : .leading)
            .padding(.horizontal, 18)
        }
        .environment(\.layoutDirection, .leftToRight)
        .environment(\.colorScheme, .dark)
        .onAppear {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { shown = true }
        }
        .accessibilityIdentifier("chat-message-menu")
        .sheet(isPresented: $selecting, onDismiss: onClose) {
            ForgeChatSelectTextSheet(text: target.text)
        }
    }

    private func row(_ title: String, _ icon: String, id: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 16))
                Spacer()
                Image(systemName: icon).font(.system(size: 15))
                    .foregroundStyle(destructive ? AnyShapeStyle(MirsaPalette.danger) : AnyShapeStyle(MirsaPalette.accentGradient))
            }
            .foregroundStyle(destructive ? MirsaPalette.danger : MirsaPalette.textPrimary)
            .padding(.horizontal, 16).frame(height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// «Select Text»: the whole message in a read-only text view so any part of it can be selected and copied.
struct ForgeChatSelectTextSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ForgeChatSelectableText(text: text)
                .padding(.horizontal, 14)
                .background(MirsaPalette.sheet.ignoresSafeArea())
                .navigationTitle(ForgeChatExtrasText.selectText)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(ForgeChatExtrasText.done) { dismiss() }.tint(MirsaPalette.accentSoft)
                            .accessibilityIdentifier("chat-select-done")
                    }
                }
        }
        .environment(\.layoutDirection, .leftToRight)
        .environment(\.colorScheme, .dark)
        .presentationDetents([.medium, .large])
        .presentationBackground(MirsaPalette.sheet)
        .accessibilityIdentifier("chat-select-sheet")
    }
}

struct ForgeChatSelectableText: UIViewRepresentable {
    let text: String
    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.isEditable = false
        v.isSelectable = true
        v.backgroundColor = .clear
        v.textColor = .white
        v.tintColor = UIColor(MirsaPalette.accent)
        v.font = .systemFont(ofSize: 17)
        v.textAlignment = .natural
        v.textContainerInset = UIEdgeInsets(top: 16, left: 2, bottom: 24, right: 2)
        v.alwaysBounceVertical = true
        v.text = text
        DispatchQueue.main.async { v.becomeFirstResponder(); v.selectAll(nil) }
        return v
    }
    func updateUIView(_ v: UITextView, context: Context) { if v.text != text { v.text = text } }
}

/// Small count badge for the «Mirsa AI» segment.
struct ForgeChatUnreadDot: View {
    let count: Int
    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)").font(.system(size: 10, weight: .bold)).monospacedDigit().foregroundStyle(.white)
                .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                .background(Capsule().fill(Color(red: 1, green: 0.23, blue: 0.19)))
                .accessibilityLabel(ForgeChatExtrasText.unread(count))
                .accessibilityIdentifier("chat-unread-badge")
        }
    }
}

/// Tab bar badge for the Tools tab (where Mirsa AI lives).
struct ForgeChatUnreadTabBadge: ViewModifier {
    @ObservedObject private var store = ForgeChatStore.shared
    @ObservedObject private var local = ForgeChatLocal.shared
    func body(content: Content) -> some View {
        let n = local.unreadCount(store.threads)
        content.badge(n)
    }
}
