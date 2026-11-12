//
//  VersionLookup.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import AsyncHTTPClient
import Foundation

public enum VersionLookup {
    public static func getVersionMetadata(
        account: inout Account,
        app: Software,
        versionID: String,
    ) async throws -> VersionMetadata {
        let client = Configuration.makeHTTPClient(redirectConfiguration: .disallow)
        defer { _ = client.shutdown() }

        let fetched: (response: [String: Any], endpoint: StoreDownloadTag.Endpoint)
        do {
            fetched = try await StoreDownloadEndpoint.fetchProductTracked(
                client: client,
                account: &account,
                app: app,
                deviceIdentifier: Configuration.deviceIdentifier,
                externalVersionID: versionID,
            )
        } catch {
            throw StoreDownloadFailure.map(error, .metadata)
        }
        let dict = fetched.response

        guard let items = dict["songList"] as? [[String: Any]], !items.isEmpty else {
            let stop: StoreDownloadTag.Stop = dict["failureType"] == nil && (dict["customerMessage"] as? String ?? "").isEmpty ? .noItems : .failure
            throw StoreDownloadFailure.answer(.metadata, fetched.endpoint, dict, stop, reason: Strings.noItemsInResponse)
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
