//
//  VersionFinder.swift
//  ApplePackage
//
//  Created by qaq on 9/14/25.
//

import AsyncHTTPClient
import Foundation

public enum VersionFinder {
    public static func list(
        account: inout Account,
        bundleIdentifier: String,
        entityType: EntityType? = nil,
        externalVersionID: String? = nil,
    ) async throws -> [String] {
        guard let countryCode = Configuration.countryCode(for: account.store) else {
            try ensureFailed(Strings.unsupportedStoreIdentifier(account.store))
        }
        let app: Software
        do {
            app = try await Lookup.lookup(bundleID: bundleIdentifier, countryCode: countryCode, entityType: entityType)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Public catalog lookup (itunes.apple.com/lookup), before any commerce request.
            throw StoreDownloadFailure(.init(operation: .versions, endpoint: .none, httpStatus: 0, stop: .lookup), reason: Strings.invalidResponse)
        }
        let resolvedExternalVersionID: String
        if let externalVersionID {
            resolvedExternalVersionID = externalVersionID
        } else if let entityType, entityType == .appleTV {
            // ipatool ListVersions pins a catalog version only for tvOS/watchOS/visionOS/macOS. For iPhone/iPad the
            // version list comes from an UNPINNED volumeStore request (latest build + softwareVersionExternalIdentifiers).
            let metadata = try await PlatformVersionLookup.lookup(
                appID: app.id,
                countryCode: countryCode,
                entityType: entityType,
            )
            resolvedExternalVersionID = metadata.externalVersionID
        } else {
            resolvedExternalVersionID = ""
        }

        let client = Configuration.makeHTTPClient(redirectConfiguration: .disallow)
        defer { _ = client.shutdown() }

        let fetched: (response: [String: Any], endpoint: StoreDownloadTag.Endpoint)
        do {
            fetched = try await StoreDownloadEndpoint.fetchProductTracked(
                client: client,
                account: &account,
                app: app,
                deviceIdentifier: Configuration.deviceIdentifier,
                externalVersionID: resolvedExternalVersionID,
                entityType: entityType ?? .iPhone,
            )
        } catch {
            throw StoreDownloadFailure.map(error, .versions)
        }
        let dict = fetched.response
        let at = fetched.endpoint

        if let failure = dict["failureType"].map({ String(describing: $0) }), !failure.isEmpty {
            switch failure {
            case "2034", "2042":
                throw StoreDownloadFailure.answer(.versions, at, dict, .failure, reason: Strings.passwordTokenExpired)
            case "9610":
                throw ApplePackageError.licenseRequired
            default:
                let reason = dict["customerMessage"] as? String == Strings.passwordChanged ? Strings.passwordTokenExpired : Strings.noItemsInResponse
                throw StoreDownloadFailure.answer(.versions, at, dict, .failure, reason: reason)
            }
        }

        guard let items = dict["songList"] as? [[String: Any]], !items.isEmpty else {
            let message = (dict["customerMessage"] as? String ?? "").isEmpty && dict["dialog"] == nil
            throw StoreDownloadFailure.answer(.versions, at, dict, message ? .noItems : .failure, reason: Strings.noItemsInResponse)
        }

        let item = items[0]
        guard let metadata = item["metadata"] as? [String: Any],
              let identifiers = metadata["softwareVersionExternalIdentifiers"] as? [Any]
        else {
            throw StoreDownloadFailure.answer(.versions, at, dict, .noVersionIDs, reason: Strings.missingVersionIdentifiers)
        }

        let result = identifiers.map { "\($0)" }
        guard !result.isEmpty else {
            throw StoreDownloadFailure.answer(.versions, at, dict, .noVersionIDs, reason: Strings.noVersionsFound)
        }

        return result
    }
}
