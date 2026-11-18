import Foundation
import ApplePackage

/// A consent-bound, single-use retry. HTTP 403 is not ownership evidence.
struct StoreFreeLicenseRecovery: Identifiable {
    let id = UUID()
    let app: MirsaStoreApp
    let externalVersionID: String?
    let revision: Int

    static func canOffer(status: UInt, price: Double?) -> Bool {
        status == 403 && price == 0
    }

    /// Called only by the visible confirmation button. Acquisition independently
    /// rechecks the current storefront's live price before any buyProduct call.
    static func retryOnce(
        consent: Bool,
        acquire: () async throws -> Void,
        download: () async throws -> URL
    ) async throws -> URL {
        guard consent else { throw CancellationError() }
        try Task.checkCancellation()
        try await acquire()
        try Task.checkCancellation()
        return try await download()
    }
}
