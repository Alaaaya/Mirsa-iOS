import Foundation

/// Only allowlisted response fields, never a request, headers, URL, or raw body.
public struct AuthenticationServiceError: Error, Sendable {
    public enum Stage: String, Sendable { case bag, sapCertificate, sapSetup, sapValidation, signing, authentication }
    public let stage: Stage
    public let transport: Bool
    public let httpStatus: Int?
    public let appleCode: String?
    public let message: String?
    public let networkCode: Int?

    public init(stage: Stage, httpStatus: Int? = nil, appleCode: Any? = nil, message: String? = nil,
                networkCode: Int? = nil, transport: Bool = false, secrets: [String] = []) {
        self.stage = stage
        self.transport = transport
        self.httpStatus = httpStatus
        let code = (appleCode as? String) ?? (appleCode as? NSNumber)?.stringValue
        self.appleCode = code.flatMap { $0.range(of: "^-?[0-9]{1,8}$", options: .regularExpression) != nil ? $0 : nil }
        self.message = Self.redact(message, secrets: secrets)
        self.networkCode = networkCode
    }

    public static func wrapping(_ error: Error, stage: Stage, transport: Bool = false) -> AuthenticationServiceError {
        if let diagnostic = error as? AuthenticationServiceError { return diagnostic }
        if let amd = error as? StoreAMDError {
            return .init(stage: stage, httpStatus: amd.httpStatus, message: amd.errorDescription)
        }
        if let auth = error as? AuthenticationError {
            return .init(stage: stage, message: auth.errorDescription)
        }
        let ns = error as NSError
        // No arbitrary errorDescription: networking errors may contain URLs or headers.
        return .init(stage: stage, networkCode: ns.domain == NSURLErrorDomain ? ns.code : nil, transport: transport)
    }

    public static func redact(_ input: String?, secrets: [String]) -> String? {
        guard var text = input, !text.isEmpty else { return nil }
        // Reject overly large messages rather than allowing a secret cut across the bound.
        guard text.utf8.count <= 4096 else { return nil }
        for secret in secrets.filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
            text = text.replacingOccurrences(of: secret, with: "[redacted]", options: .caseInsensitive)
        }
        for pattern in [
            "(?i)https?://[^\\s<>]+",
            "(?i)[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}",
            "(?i)(password|token|cookie|authorization|signature|dsid|guid)\\s*[:=]\\s*[^\\s,;]+",
            "[A-Za-z0-9+/=_-]{32,}", "[0-9]{6,}"
        ] {
            text = text.replacingOccurrences(of: pattern, with: "[redacted]", options: .regularExpression)
        }
        text = text.components(separatedBy: .controlCharacters).joined(separator: " ")
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return String(text.prefix(320))
    }
}
