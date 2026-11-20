import Foundation

/// Live tracing (التتبع الحي) for Premium Unlock: the MirsaUnlock dylib
/// records calls to candidate getters while the user taps a paid feature
/// in the target app, one JSON line per call. The trace comes back to
/// Mirsa on the shared pasteboard (the dylib's floating "● Trace"
/// button copies it; the target sandbox itself is unreadable to Mirsa,
/// and its App Group cannot be shared — see MirsaUnlock.m header).
///
/// This file is the Mirsa-side half: parse the pasted JSON lines,
/// suggest the right "returns" value per call (same rules as the limit
/// hooks in PremiumScanner), pick the strongest premium-check
/// candidate, and ask the Forge AI for a custom hook suggestion.
/// The AI is best-effort: when the server has no LLM configured
/// (503 llm_not_configured) or does not answer, tracing and manual
/// hook selection keep working untouched.
enum PremiumTrace {

    enum Kind: String, Codable {
        case bool, int, object, void, number
    }

    /// One recorded call, in order. `returns` is the observed return
    /// value as text ("YES" / "NO" / "3" / "nil" / class name …).
    struct Entry: Identifiable, Equatable, Codable {
        var id: UUID = UUID()
        var time: Date
        var className: String
        var selector: String
        var returns: String
        var kind: Kind

        /// "HH:mm:ss" for the row, local time.
        var timeText: String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f.string(from: time)
        }

        /// "-[Class selector]" for the row.
        var callText: String { "-[" + className + " " + selector + "]" }
    }

    /// Parse pasted trace text (JSON lines). Header lines
    /// ({"event":"trace-start",…}) are skipped. At most 500 entries,
    /// oldest first. Returns [] for empty / unparsable text — the
    /// caller shows "no trace yet", never a crash.
    static func parse(_ text: String) -> [Entry] {
        var out: [Entry] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["event"] == nil,
                  let selector = obj["selector"] as? String, !selector.isEmpty else { continue }
            let ms = (obj["t"] as? Double) ?? 0
            let time = ms > 0 ? Date(timeIntervalSince1970: ms / 1000.0) : Date()
            let returns = (obj["returns"] as? String) ?? ""
            let kind: Kind
            if let raw = obj["kind"] as? String, let parsed = Kind(rawValue: raw) {
                kind = parsed
            } else if returns == "YES" || returns == "NO" {
                kind = .bool
            } else if returns.isEmpty {
                kind = .void
            } else if Double(returns) != nil {
                kind = .int
            } else {
                kind = .object
            }
            out.append(Entry(time: time,
                             className: (obj["class"] as? String) ?? "?",
                             selector: selector, returns: returns, kind: kind))
            if out.count >= 500 { break }
        }
        return out.sorted { $0.time < $1.time }
    }

    /// The "returns" value the dylib should use for this call — same
    /// rules as the limit hooks (PremiumScanner.returnsFor): YES for a
    /// premium BOOL getter, 999 ("count") for a remaining counter, 0
    /// ("zero") for a used counter. Name-based rules first: a
    /// "limit reached / expired" check must return NO, not YES. nil
    /// means no safe suggestion (object getters other than trial dates
    /// cannot be faked generically) — manual choice only.
    static func suggestedReturns(for entry: Entry) -> String? {
        let lower = entry.selector.lowercased()
        if lower.contains("reachedlimit") || lower.contains("limitreached")
            || lower.contains("islimit") || lower.contains("expired")
            || lower.contains("isjailbroken") || lower.contains("needsupdate")
            || lower.contains("isupdaterequired") || lower.contains("updateavailable") {
            return "no"
        }
        if lower.contains("remaining") || lower.contains("left")
            || lower.contains("usesremaining") {
            return "count"
        }
        if lower.contains("used") || lower.contains("quota")
            || lower.contains("maxfree") || lower.contains("count") {
            return "zero"
        }
        switch entry.kind {
        case .bool: return "yes"
        case .int: return "count"
        case .number: return "count"
        case .void: return "noop"
        case .object:
            if lower.contains("trialenddate") || lower.contains("enddate") {
                return "future"
            }
            return nil
        }
    }

    /// The strongest premium-check candidate: the most-called selector
    /// whose name matches a scan pattern (premium / limit symbols),
    /// preferring one that answered NO / 0 (the app refusing premium),
    /// then the most recent. nil when the trace is empty.
    static func strongestCandidate(in entries: [Entry]) -> Entry? {
        guard !entries.isEmpty else { return nil }
        let patterns = PremiumPatternStore.shared.snapshot()
        let lowered = (patterns.premiumSymbols + patterns.limitSymbols)
            .map { $0.lowercased() }
        func matchesPatterns(_ selector: String) -> Bool {
            let lower = selector.lowercased()
            return lowered.contains { lower.contains($0) }
        }
        var bySelector: [String: [Entry]] = [:]
        for e in entries { bySelector[e.selector, default: []].append(e) }
        var best: (entry: Entry, score: Int)?
        for (_, group) in bySelector {
            let first = group[0]
            var score = matchesPatterns(first.selector) ? 10 : 0
            if group.contains(where: { $0.returns == "NO" || $0.returns == "0" }) {
                score += 5
            }
            score += min(group.count, 5)
            let latest = group.max(by: { $0.time < $1.time }) ?? first
            if best == nil || score > best!.score
                || (score == best!.score && latest.time > best!.entry.time) {
                best = (latest, score)
            }
        }
        return best?.entry
    }

    // MARK: - AI hook suggestion

    /// One hook the AI suggests, shown to the user for confirmation
    /// before anything is added to the config. Never applied blindly.
    struct Suggestion: Equatable {
        var className: String
        var selector: String
        var returns: String
        var reason: String
    }

    static let validReturns = ["yes", "no", "count", "zero", "future", "noop", "dismiss"]

    /// Extract {"class","selector","returns","reason"} from the AI
    /// reply text and validate it strictly: the selector MUST be one
    /// of the traced selectors (an untraced suggestion is rejected —
    /// the model must not invent methods), the class name charset and
    /// the "returns" value must be known. nil = unusable reply.
    static func parseAISuggestion(_ text: String, tracedSelectors: Set<String>) -> Suggestion? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"), start <= end else { return nil }
        let json = String(text[start...end])
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let selector = obj["selector"] as? String,
              !selector.isEmpty, tracedSelectors.contains(selector),
              selector.range(of: "^[A-Za-z_][A-Za-z0-9_:]{0,127}$", options: .regularExpression) != nil,
              let returns = obj["returns"] as? String, validReturns.contains(returns) else { return nil }
        let className = (obj["class"] as? String) ?? ""
        guard className.isEmpty
                || className.range(of: "^[A-Za-z_][A-Za-z0-9_.$]{0,127}$", options: .regularExpression) != nil else { return nil }
        let reason = (obj["reason"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Suggestion(className: className, selector: selector, returns: returns,
                          reason: String(reason.prefix(300)))
    }

    /// Forge AI hook suggestion. Uses the existing Forge AI channel
    /// (ForgeClient.post, same chat-send / chat-read contract ForgeChat
    /// uses) in a FRESH thread, so no existing chat is polluted, and
    /// waits for the assistant reply (bounded: 9 polls × 5 s).
    /// Throws the server's own localized failure — including
    /// 503 llm_not_configured ("خدمة الذكاء الاصطناعي مو مفعّلة على
    /// السيرفر بعد") — and the caller shows it while manual selection
    /// keeps working. There is no dedicated hook-suggestion endpoint:
    /// "suggest" returns generic tweak ideas and "generate" returns
    /// Logos code, so the chat channel is the right reuse.
    enum AI {
        /// GET ?action=status → {"llm": Bool}. nil = could not check
        /// (offline / auth); the caller may still try the suggestion
        /// and surface the real error.
        static func llmAvailable() async -> Bool? {
            guard let out = try? await ForgeClient.get(["action": "status"]) else { return nil }
            return out["llm"] as? Bool
        }

        static func suggest(appName: String, bundleID: String, scanSummary: String,
                            entries: [Entry]) async throws -> Suggestion {
            let traced = Set(entries.map(\.selector))
            let lines = entries.prefix(30).map {
                "\($0.timeText) -[\($0.className) \($0.selector)] -> \($0.returns) (\($0.kind.rawValue))"
            }.joined(separator: "\n")
            let prompt = """
            You are helping unlock premium features of an iOS app by hooking ONE Objective-C method. Reply ONLY with JSON: {"class": "...", "selector": "...", "returns": "yes|no|count|zero|future|noop|dismiss", "reason": "..."}.
            "class" may be "" (any class). "returns": yes = BOOL YES, no = BOOL NO, count = integer 999, zero = integer 0, future = date 10 years out, noop = void do-nothing, dismiss = dismiss view controller.
            Pick the selector from the trace below that is the premium check (the one whose return value decides whether the paid feature opens). Never invent a selector that is not in the trace.
            App: \(appName) (\(bundleID))
            Static scan: \(scanSummary)
            Live trace (time, call, observed return):
            \(lines)
            """
            let threadID = UUID()
            let body: [String: Any] = [
                "action": "chat-send",
                "id": UUID().uuidString.lowercased(),
                "threadID": threadID.uuidString.lowercased(),
                "newThread": true,
                "text": prompt,
                "language": AppLanguageStore.snapshot.rawValue,
            ]
            _ = try await ForgeClient.post(body)
            // The AI answer arrives asynchronously; poll chat-read.
            struct Lossy: Decodable {
                let value: ForgeChatMessage?
                init(from d: Decoder) throws { value = try? ForgeChatMessage(from: d) }
            }
            struct W: Decodable { let messages: [Lossy] }
            for _ in 0..<9 {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let data = try? await ForgeClient.post(
                    ["action": "chat-read", "threadID": threadID.uuidString.lowercased()]),
                      let raw = try? JSONDecoder().decode(W.self, from: data) else { continue }
                for m in raw.messages.compactMap(\.value) where m.role != "user" {
                    guard let text = m.text, !text.isEmpty,
                          let suggestion = PremiumTrace.parseAISuggestion(text, tracedSelectors: traced) else { continue }
                    return suggestion
                }
            }
            throw ForgeClient.Failure.message(tr(
                "The AI did not answer. Try again, or add the hook manually.",
                "الذكاء الاصطناعي ما ردّ. جرّب مرة تانية، أو أضِف الخطّافة يدويًا.",
                ckb: "زیرەکی دەستکرد وەڵامی نەدایەوە. دووبارە تاقی بکەرەوە، یان هۆکەکە بە دەست زیاد بکە.",
                kmr: "AI bersiv neda. Dîsa biceribîne, an hookê bi destan lê zêde bike."))
        }
    }
}
