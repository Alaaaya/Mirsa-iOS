//
//  VersionLookup.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import AsyncHTTPClient
import Foundation

public enum VersionLookup {
    /// A version label does not require releaseDate. Some official responses omit it.
    public static func getVersionDisplayName(account: inout Account, app: Software, versionID: String) async throws -> String {
        let client = Configuration.makeHTTPClient(redirectConfiguration: .disallow)
        defer { _ = client.shutdown() }
        let dict = try await StoreDownloadEndpoint.fetchProductWithFallback(client: client, account: &account,
            app: app, deviceIdentifier: Configuration.deviceIdentifier, externalVersionID: versionID)
        return try displayName(dict, app: app, versionID: versionID)
    }

    static func displayName(_ dict: [String: Any], app: Software, versionID: String) throws -> String {
        guard let items = dict["songList"] as? [[String: Any]], items.count == 1,
              let metadata = items.first?["metadata"] as? [String: Any],
              metadata["itemId"].map({ String(describing: $0) }) == String(app.id),
              metadata["softwareVersionBundleId"] as? String == app.bundleID,
              metadata["softwareVersionExternalIdentifier"].map({ String(describing: $0) }) == versionID,
              let name = metadata["bundleShortVersionString"] as? String,
              !name.isEmpty, name.utf8.count <= 128,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { try ensureFailed(Strings.invalidResponse) }
        return name
    }

    public static func getVersionMetadata(
        account: inout Account,
        app: Software,
        versionID: String,
    ) async throws -> VersionMetadata {
        let client = Configuration.makeHTTPClient(redirectConfiguration: .disallow)
        defer { _ = client.shutdown() }

        let dict = try await StoreDownloadEndpoint.fetchProductWithFallback(
            client: client,
            account: &account,
            app: app,
            deviceIdentifier: Configuration.deviceIdentifier,
            externalVersionID: versionID,
        )

        guard let items = dict["songList"] as? [[String: Any]], !items.isEmpty else {
            try ensureFailed(Strings.noItemsInResponse)
        }

        let item = items[0]
        guard let metadata = item["metadata"] as? [String: Any] else {
            try ensureFailed(Strings.missingMetadata)
        }

        guard let bundleShortVersionString = metadata["bundleShortVersionString"] as? String else {
            try ensureFailed(Strings.missingBundleShortVersionString)
        }

        guard let releaseDateString = metadata["releaseDate"] as? String,
              let releaseDate = ISO8601DateFormatter().date(from: releaseDateString)
        else {
            try ensureFailed(Strings.missingOrInvalidReleaseDate)
        }

        return VersionMetadata(displayVersion: bundleShortVersionString, releaseDate: releaseDate)
    }
}
