import Foundation

/// Manual-queue receipt: the server saved the Create request for Kat; nothing was built.
struct ForgeQueuedReceipt: Equatable {
    let threadID: String
    let originalID: String
    let reviewID: String?
    let replayed: Bool
}

enum ForgeCreateOutcome {
    case generated([String: Any])
    case queued(ForgeQueuedReceipt)
}

enum ForgeQueued {
    private static let uuid = try! NSRegularExpression(pattern: "^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$")
    static func isUUID(_ s: String) -> Bool { uuid.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }

    /// Strict decoder. A queued receipt needs saved == true, status == "manual-queue", the thread we sent,
    /// a well-formed original ID and no code. HTTP 202 is accepted only when it is such a receipt.
    static func decode(status: Int, data: Data, expectedThreadID: String) throws -> ForgeCreateOutcome {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw ForgeClient.Failure.message("Bad response") }
        if status == 202 || (o["status"] as? String) == "manual-queue" {
            guard o["saved"] as? Bool == true, o["status"] as? String == "manual-queue", o["code"] == nil,
                  let thread = o["threadID"] as? String, thread.lowercased() == expectedThreadID.lowercased(),
                  let original = o["originalID"] as? String, isUUID(original.lowercased()) else {
                throw ForgeClient.Failure.message("Bad response")
            }
            var review = o["reviewID"] as? String
            if let r = review, !isUUID(r.lowercased()) { review = nil }
            return .queued(ForgeQueuedReceipt(threadID: thread.lowercased(), originalID: original.lowercased(), reviewID: review, replayed: o["replayed"] as? Bool == true))
        }
        guard status == 200 else { throw ForgeClient.Failure.message("Bad response") }
        return .generated(o)
    }

    /// Request and thread IDs are stored BEFORE the call, so a retry of the same request reuses them.
    static func ids(for body: [String: Any], defaults: UserDefaults = .standard) -> (id: String, thread: String) {
        let canon = String(data: (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data(), encoding: .utf8) ?? ""
        let key = "mirsa.forge.queued." + String(canon.hashValue, radix: 16) + "." + String(canon.utf8.count)
        if let v = defaults.string(forKey: key + ".id"), let t = defaults.string(forKey: key + ".t") { return (v, t) }
        let v = UUID().uuidString.lowercased(), t = UUID().uuidString.lowercased()
        defaults.set(v, forKey: key + ".id"); defaults.set(t, forKey: key + ".t")
        return (v, t)
    }
    static func forget(_ body: [String: Any], defaults: UserDefaults = .standard) {
        let canon = String(data: (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data(), encoding: .utf8) ?? ""
        let key = "mirsa.forge.queued." + String(canon.hashValue, radix: 16) + "." + String(canon.utf8.count)
        defaults.removeObject(forKey: key + ".id"); defaults.removeObject(forKey: key + ".t")
    }

    static var notice: String {
        storeText("Your request arrived and is in the queue. The tweak will show up here.",
                  "طلبك وصل وبالدور، رح يوصلك التويك هون",
                  de: "Deine Anfrage ist angekommen und in der Warteschlange. Das Tweak erscheint hier.",
                  ckb: "داواکارییەکەت گەیشت و لە ڕیزدایە، تویکەکە لێرە دێت.",
                  kmr: "Daxwaza te gihîşt û di rêzê de ye, tweak li vir xuya dibe.")
    }
}

extension ForgeClient {
    static func createCall(_ body: [String: Any]) async throws -> ForgeCreateOutcome {
        let ids = ForgeQueued.ids(for: body)
        var b = body; b["id"] = ids.id; b["threadID"] = ids.thread
        let (data, status) = try await postStatus(b, allowAccepted: true)
        let out = try ForgeQueued.decode(status: status, data: data, expectedThreadID: ids.thread)
        ForgeQueued.forget(body)
        return out
    }
}
