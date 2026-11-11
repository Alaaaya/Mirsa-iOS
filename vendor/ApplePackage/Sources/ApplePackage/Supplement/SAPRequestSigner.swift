import Foundation

/// Stateful signing of the exact bytes sent in an authentication request.
/// Reuse the same instance for retries, redirects, and verification-code calls.
public protocol SAPRequestSigning: Sendable { func sign(_ body: Data) async throws -> Data }

extension SAPSigner: SAPRequestSigning {}

public enum AuthenticationError: LocalizedError, Equatable, Sendable {
    case verificationCodeRequired
    /// A code was submitted and Apple did not accept it.
    case codeRejected
    /// The code was not exactly six ASCII digits; nothing was sent.
    case invalidVerificationCode

    public var errorDescription: String? {
        switch self {
        case .verificationCodeRequired: Strings.authRequiresVerificationCode
        case .codeRejected: "The verification code was rejected."
        case .invalidVerificationCode: "Enter exactly 6 digits."
        }
    }
}
