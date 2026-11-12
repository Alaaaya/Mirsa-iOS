import Foundation

/// Secret-free summary of why a product download / version-list request stopped, for owner reports.
///
/// Only Apple's numeric `failureType`, the numeric `metrics.messageCode`,
/// `customerMessage` when it is an Apple key (`MZ...`, `AMD-Action...`) or one of a fixed set of known Apple texts
/// (mapped to a slug), the HTTP status, which endpoint answered, whether a dialog was present, the item count and the
/// stage that stopped. Never a DSID, token, cookie, email, guid, URL, header value, sinf byte or free text.
public struct StoreDownloadTag: Sendable, Equatable {
    public enum Operation: String, Sendable { case download, versions, metadata }
    public enum Endpoint: String, Sendable { case volume, redownload, update, none }
    public enum Stop: String, Sendable {
        /// Apple returned a failureType and/or customerMessage.
        case failure
        /// HTTP 200 without any item in songList.
        case noItems = "no-items"
        case noURL = "no-url"
        case noMetadata = "no-metadata"
        case noSinf = "no-sinf"
        case badSinf = "bad-sinf"
        case noVersion = "no-version"
        case noVersionIDs = "no-version-ids"
        /// Non-200 HTTP status from the commerce endpoint.
        case http
        case redirect
        /// Body was not a property list.
        case parse
        /// A recovery (redownload/update) response did not match the requested app or version.
        case recovery
        /// Catalog version lookup (uclient-api) needed before redownload failed.
        case lookup
    }

    public let operation: Operation
    public let endpoint: Endpoint
    public let failureType: String
    public let messageCode: String
    public let message: String
    public let httpStatus: Int
    public let dialog: Bool
    public let items: Int
    public let stop: Stop

    public init(operation: Operation = .download, endpoint: Endpoint, response: [String: Any]? = nil,
                httpStatus: Int, stop: Stop) {
        self.operation = operation
        self.endpoint = endpoint
        self.failureType = StoreDownloadTag.failureCode(response?["failureType"])
        self.messageCode = StoreDownloadTag.failureCode((response?["metrics"] as? [String: Any])?["messageCode"])
        let dialog = response?["dialog"] as? [String: Any]
        self.message = Self.message(response?["customerMessage"] ?? dialog?["message"])
        self.httpStatus = max(0, min(httpStatus, 999))
        self.dialog = dialog != nil
        self.items = min((response?["songList"] as? [Any])?.count ?? 0, 9)
        self.stop = stop
    }

    private init(copy: StoreDownloadTag, operation: Operation) {
        self.operation = operation
        endpoint = copy.endpoint; failureType = copy.failureType; messageCode = copy.messageCode
        message = copy.message; httpStatus = copy.httpStatus; dialog = copy.dialog; items = copy.items; stop = copy.stop
    }

    public func with(operation: Operation) -> StoreDownloadTag { .init(copy: self, operation: operation) }

    /// `[dl:download at=volume ft=2042 mc=none msg=sign-in http=200 dlg=0 items=0 stop=failure]`
    public var text: String {
        "[dl:\(operation.rawValue) at=\(endpoint.rawValue) ft=\(failureType) mc=\(messageCode) msg=\(message) http=\(httpStatus) dlg=\(dialog ? 1 : 0) items=\(items) stop=\(stop.rawValue)]"
    }

    /// Known Apple texts (never account-specific) map to a slug; Apple keys pass; anything else is `other`.
    static func message(_ value: Any?) -> String {
        guard let raw = value as? String else { return "none" }
        let text = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        if text.isEmpty { return "none" }
        let key = StoreDownloadTag.keyLike(text)
        if key != "other" { return key }
        let lower = text.lowercased()
        let known: [(String, String)] = [
            ("your password has changed.", "password-changed"),
            ("sign in to the itunes store", "sign-in"),
            ("sign-in required", "sign-in"),
            ("redownload unavailable with this apple account", "redownload-unavailable"),
            ("subscription required", "subscription-required"),
            ("your account is disabled.", "account-disabled"),
        ]
        if let match = known.first(where: { $0.0 == lower }) { return match.1 }
        if lower == "no longer available" || lower.hasSuffix(" no longer available") { return "no-longer-available" }
        if lower.utf8.count <= 96, lower.contains("temporarily unavailable") { return "temporarily-unavailable" }
        return "other"
    }
}

/// A download / version-list failure with Apple's secret-free reason tag. The description keeps the original
/// (English, ApplePackage) message; apps should show their own localized text plus `tag.text`.
public struct StoreDownloadFailure: Error, LocalizedError, Sendable {
    public let tag: StoreDownloadTag
    public let reason: String
    public init(_ tag: StoreDownloadTag, reason: String) { self.tag = tag; self.reason = reason }
    public var errorDescription: String? { reason + " " + tag.text }
    func with(operation: StoreDownloadTag.Operation) -> StoreDownloadFailure { .init(tag.with(operation: operation), reason: reason) }
}

extension StoreDownloadFailure {
    /// Adds the operation to a chain failure. Others pass unchanged: StoreProductDiagnostic (Apple's own bounded
    /// HTTP / failureType answer, already shown by the app), cancellation, AMD, license required, transport.
    static func map(_ error: Error, _ operation: StoreDownloadTag.Operation) -> Error {
        if let failure = error as? StoreDownloadFailure { return failure.with(operation: operation) }
        return error
    }

    /// Apple answered 200 but the answer cannot be used; `response` is read only for the secret-free tag.
    static func answer(_ operation: StoreDownloadTag.Operation, _ endpoint: StoreDownloadTag.Endpoint,
                       _ response: [String: Any], _ stop: StoreDownloadTag.Stop, reason: String) -> StoreDownloadFailure {
        .init(.init(operation: operation, endpoint: endpoint, response: response, httpStatus: 200, stop: stop), reason: reason)
    }
}

extension StoreDownloadTag {
    /// Numeric Apple code (e.g. 5002, -5000), `none` when absent or empty, `other` for anything else.
    static func failureCode(_ value: Any?) -> String {
        guard let value else { return "none" }
        let text = ((value as? String) ?? (value as? NSNumber)?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "none" }
        return text.range(of: "^-?[0-9]{1,8}$", options: .regularExpression) != nil ? text : "other"
    }

    /// Only Apple's identifier keys pass; any human text (which may echo the account) becomes `other`.
    static func keyLike(_ value: Any?) -> String {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return "none" }
        guard text.utf8.count <= 96 else { return "other" }
        let patterns = [
            "^MZ[A-Za-z0-9]{1,32}(\\.[A-Za-z0-9_]{1,48}){1,4}$",
            "^AMD-Action(:{1,2}[A-Za-z]{1,4})?$",
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil } ? text : "other"
    }
}
