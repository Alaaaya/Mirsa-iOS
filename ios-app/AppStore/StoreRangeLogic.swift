import Foundation

/// Pure HTTP Range rules for resuming App Store downloads. No I/O, fully unit-tested.
/// A partial may only be continued when the server proves it is the SAME representation.
struct StoreResumeState: Codable, Equatable {
    var version = 1
    var etag: String?          // strong ETags only
    var lastModified: String?  // only when it parses as an HTTP date
    var total: Int64?
    var bytes: Int64 = 0

    /// A value we can send as If-Range and compare on a 206. Without one we never resume.
    var hasValidator: Bool { etag != nil || lastModified != nil }
    var ifRangeValue: String? { etag ?? lastModified }
}

struct StoreContentRange: Equatable {
    let start: Int64
    let end: Int64
    let total: Int64?
}

struct StoreResponseHeaders: Equatable {
    var etag: String?
    var lastModified: String?
    var contentRange: String?
    var contentLength: String?
    var contentEncoding: String?
}

enum StoreRangeDecision: Equatable {
    /// 206 at the exact offset: append `length` bytes, `total` is the full size.
    case append(length: Int64, total: Int64)
    /// 200: a whole new body follows (old bytes are discarded).
    case fullBody(total: Int64?)
    /// The partial can not be trusted: cancel and fetch again from byte zero without Range.
    case restartFromZero
    case fail
}

enum StoreRangeLogic {
    static let maxBytes: Int64 = 4 * 1024 * 1024 * 1024

    static func number(_ value: String?) -> Int64? {
        guard let value else { return nil }
        let t = value.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.count <= 19, t.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        return Int64(t)
    }

    static func isStrongETag(_ value: String?) -> Bool {
        guard let v = value?.trimmingCharacters(in: .whitespaces), v.count >= 2 else { return false }
        return v.hasPrefix("\"") && v.hasSuffix("\"") && !v.dropFirst().dropLast().contains("\"")
    }

    static func strongETag(_ value: String?) -> String? {
        isStrongETag(value) ? value?.trimmingCharacters(in: .whitespaces) : nil
    }

    static func httpDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return f.date(from: value.trimmingCharacters(in: .whitespaces))
    }

    static func validLastModified(_ value: String?) -> String? {
        httpDate(value) == nil ? nil : value?.trimmingCharacters(in: .whitespaces)
    }

    /// "bytes START-END/TOTAL". Total may be "*". Everything else is rejected.
    static func parseContentRange(_ value: String?) -> StoreContentRange? {
        guard let value, value.hasPrefix("bytes ") else { return nil }
        let rest = value.dropFirst(6).trimmingCharacters(in: .whitespaces)
        let halves = rest.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard halves.count == 2 else { return nil }
        let range = halves[0].split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard range.count == 2, let s = number(range[0]), let e = number(range[1]), s <= e else { return nil }
        if halves[1] == "*" { return .init(start: s, end: e, total: nil) }
        guard let t = number(halves[1]), e < t else { return nil }
        return .init(start: s, end: e, total: t)
    }

    static func isIdentity(_ encoding: String?) -> Bool {
        guard let e = encoding?.trimmingCharacters(in: .whitespaces).lowercased() else { return true }
        return e.isEmpty || e == "identity"
    }

    /// What to remember from a fresh 200/206 response.
    static func freshState(_ h: StoreResponseHeaders, total: Int64?) -> StoreResumeState {
        StoreResumeState(etag: strongETag(h.etag), lastModified: validLastModified(h.lastModified), total: total, bytes: 0)
    }

    static func decide(status: Int, offset: Int64, state: StoreResumeState,
                       headers h: StoreResponseHeaders, maxBytes: Int64 = StoreRangeLogic.maxBytes) -> StoreRangeDecision {
        guard isIdentity(h.contentEncoding) else { return .fail }
        let length = h.contentLength == nil ? nil : number(h.contentLength)
        if h.contentLength != nil && length == nil { return .fail }
        switch status {
        case 200:
            if let length { guard length > 0, length <= maxBytes else { return .fail } }
            return .fullBody(total: length)
        case 206:
            guard offset > 0 else { return .fail }
            guard state.hasValidator else { return .restartFromZero }
            if let etag = state.etag {
                guard strongETag(h.etag) == etag else { return .restartFromZero }
            } else if let lm = state.lastModified {
                guard validLastModified(h.lastModified) == lm else { return .restartFromZero }
            }
            guard let cr = parseContentRange(h.contentRange), cr.start == offset,
                  let total = cr.total, total > 0, total <= maxBytes,
                  cr.end == total - 1, offset < total else { return .restartFromZero }
            if let known = state.total, known != total { return .restartFromZero }
            let expected = cr.end - cr.start + 1
            guard let length, length == expected else { return .restartFromZero }
            return .append(length: expected, total: total)
        case 416:
            // Never trust a cached total to call the file complete.
            return offset > 0 ? .restartFromZero : .fail
        default:
            return .fail
        }
    }
}
