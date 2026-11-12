import Foundation

/// Secret-free summary of why a sign-in request stopped, for owner reports.
///
/// Only these values are ever kept: Apple's numeric `failureType`, `customerMessage` when it is an
/// Apple key-like identifier (`MZ...` or `AMD-Action...`), the HTTP status, which AMD action was
/// requested, the step (1 password, 2 code) and the stage that stopped the call. Never a password,
/// code, email, token, cookie, header value, URL, challenge byte or free text.
public struct AuthenticationTag: Sendable, Equatable {
    public enum Kind: String, Sendable { case code, password, rejected, amd, failure, transport, redirect }
    public enum Stop: String, Sendable {
        /// Classified from Apple's answer before any device-registration handling.
        case classify
        /// Classified after the response carried no further AMD action.
        case result
        /// AMD re-send budget used up; stopped before provisioning or re-sending.
        case amdBudget = "amd-budget"
        /// The AMD action itself could not be completed (parse, provisioning, reset).
        case amdAction = "amd-action"
        /// No HTTP response.
        case transport
        case redirect
    }

    public let kind: Kind
    public let failureType: String
    public let message: String
    public let httpStatus: Int
    public let amd: String
    public let step: Int
    public let stop: Stop

    public init(kind: Kind, failureType: Any?, customerMessage: Any?, httpStatus: Int, amdAction: String?, step: Int, stop: Stop) {
        self.kind = kind
        self.failureType = Self.failureCode(failureType)
        self.message = Self.keyLike(customerMessage)
        self.httpStatus = max(0, min(httpStatus, 999))
        self.amd = Self.action(amdAction)
        self.step = step == 2 ? 2 : 1
        self.stop = stop
    }

    /// `[auth:code ft=5005 msg=MZFinance.BadLogin.Configurator_message http=200 amd=none step=2 stop=classify]`
    public var text: String {
        "[auth:\(kind.rawValue) ft=\(failureType) msg=\(message) http=\(httpStatus) amd=\(amd) step=\(step) stop=\(stop.rawValue)]"
    }

    /// Numeric Apple code (e.g. 5005, -5000), `none` when absent or empty, `other` for anything else.
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

    static func action(_ value: String?) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !value.isEmpty else { return "none" }
        return value == "SP" || value == "RP" ? value : "other"
    }
}
