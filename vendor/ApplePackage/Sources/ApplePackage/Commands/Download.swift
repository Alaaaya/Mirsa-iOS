//
//  Download.swift
//  ApplePackage
//
//  Created by qaq on 9/15/25.
//

import AsyncHTTPClient
import Foundation

public enum Download {
    public static func download(
        account: inout Account,
        app: Software,
        externalVersionID: String? = nil,
        entityType: EntityType = .iPhone,
    ) async throws -> DownloadOutput {
        let client = Configuration.makeHTTPClient(redirectConfiguration: .disallow)
        defer { _ = client.shutdown() }

        let fetched: (response: [String: Any], endpoint: StoreDownloadTag.Endpoint)
        do {
            fetched = try await StoreDownloadEndpoint.fetchProductTracked(
                client: client,
                account: &account,
                app: app,
                deviceIdentifier: Configuration.deviceIdentifier,
                externalVersionID: externalVersionID ?? "",
                entityType: entityType,
            )
        } catch {
            throw StoreDownloadFailure.map(error, .download)
        }
        let dict = fetched.response
        let at = fetched.endpoint

        // Same order as ipatool Download: token/sign-in, license, then any failureType / customerMessage.
        if let failure = dict["failureType"].map({ String(describing: $0) }), !failure.isEmpty {
            let customerMessage = dict["customerMessage"] as? String
            switch failure {
            case "2034", "2042":
                throw StoreDownloadFailure.answer(.download, at, dict, .failure, reason: Strings.passwordTokenExpired)
            case "9610":
                throw ApplePackageError.licenseRequired
            default:
                let reason = customerMessage == Strings.passwordChanged ? Strings.passwordTokenExpired : "\(Strings.downloadFailed): \(failure)"
                throw StoreDownloadFailure.answer(.download, at, dict, .failure, reason: reason)
            }
        }

        guard let items = dict["songList"] as? [[String: Any]], !items.isEmpty else {
            let message = (dict["customerMessage"] as? String ?? "").isEmpty && dict["dialog"] == nil
            throw StoreDownloadFailure.answer(.download, at, dict, message ? .noItems : .failure, reason: Strings.noItemsInResponse)
        }

        let item = items[0]
        guard let url = item["URL"] as? String, !url.isEmpty else {
            throw StoreDownloadFailure.answer(.download, at, dict, .noURL, reason: Strings.missingDownloadURL)
        }

        guard var metadata = item["metadata"] as? [String: Any] else {
            throw StoreDownloadFailure.answer(.download, at, dict, .noMetadata, reason: Strings.missingMetadata)
        }

        let version = (metadata["bundleShortVersionString"] as? String)
        let bundleVersion = metadata["bundleVersion"] as? String

        guard let version, let bundleVersion else {
            throw StoreDownloadFailure.answer(.download, at, dict, .noVersion, reason: Strings.missingRequiredInfo)
        }

        metadata["apple-id"] = account.email
        metadata["userName"] = account.email

        let iTunesMetadata = try PropertyListSerialization.data(
            fromPropertyList: metadata,
            format: .binary,
            options: 0,
        )

        var sinfs: [Sinf] = []
        if let sinfData = item["sinfs"] as? [[String: Any]] {
            for sinfItem in sinfData {
                if let id = sinfItem["id"] as? Int64,
                   let data = sinfItem["sinf"] as? Data
                {
                    sinfs.append(Sinf(id: id, sinf: data))
                } else {
                    throw StoreDownloadFailure.answer(.download, at, dict, .badSinf, reason: Strings.invalidSinfItem)
                }
            }
        }
        guard !sinfs.isEmpty else {
            throw StoreDownloadFailure.answer(.download, at, dict, .noSinf, reason: Strings.noSinfFound)
        }

        return DownloadOutput(
            downloadURL: url,
            sinfs: sinfs,
            bundleShortVersionString: version,
            bundleVersion: bundleVersion,
            iTunesMetadata: iTunesMetadata,
        )
    }
}
