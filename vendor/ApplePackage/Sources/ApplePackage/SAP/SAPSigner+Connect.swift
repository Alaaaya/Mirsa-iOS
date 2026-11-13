import AsyncHTTPClient
import Foundation

public extension SAPSigner {
    /// Establish protocol-200 state using Apple's certificate and two-round setup service.
    static func connect() async throws -> SAPSigner {
        let client = Configuration.makeHTTPClient(redirectConfiguration: .disallow)
        defer { _ = client.shutdown() }
        func exchange(url: String, payload: Data? = nil, key: String, stage: AuthenticationServiceError.Stage) async throws -> Data {
            let body = try payload.map {
                try PropertyListSerialization.data(fromPropertyList: ["sign-sap-setup-buffer": $0], format: .xml, options: 0)
            }
            guard var target = URL(string: url) else { throw AuthenticationServiceError(stage: stage) }
            var finalResponse: HTTPClient.Response?
            for hop in 0...3 {
                guard target.scheme == "https", let host = target.host?.lowercased(),
                      host.hasSuffix(".apple.com") || host.hasSuffix(".mzstatic.com"),
                      target.user == nil, target.password == nil, target.port == nil || target.port == 443 else {
                    throw AuthenticationServiceError(stage: stage)
                }
                let request = try HTTPClient.Request(
                    url: target.absoluteString, method: body == nil ? .GET : .POST,
                    headers: ["User-Agent": Configuration.userAgent, "Content-Type": "application/x-apple-plist"],
                    body: body.map { .data($0) })
                let accumulator = ResponseAccumulator(request: request, maxBodySize: 2 * 1024 * 1024)
                let response: HTTPClient.Response
                do { response = try await client.execute(request: request, delegate: accumulator).futureResult.get() }
                catch { throw AuthenticationServiceError.wrapping(error, stage: stage, transport: true) }
                if [301, 302, 303, 307, 308].contains(Int(response.status.code)) {
                    guard hop < 3, let location = response.headers.first(name: "location"),
                          let next = URL(string: location, relativeTo: target)?.absoluteURL else {
                        throw AuthenticationServiceError(stage: stage, httpStatus: Int(response.status.code))
                    }
                    target = next
                    continue
                }
                finalResponse = response
                break
            }
            guard let response = finalResponse else { throw AuthenticationServiceError(stage: stage) }
            guard response.status == .ok, let buffer = response.body, buffer.readableBytes <= 2 * 1024 * 1024,
                  let plist = try PropertyListSerialization.propertyList(from: Data(buffer.readableBytesView), format: nil) as? [String: Any],
                  let data = plist[key] as? Data, !data.isEmpty, data.count <= 1 << 20
            else { throw AuthenticationServiceError(stage: stage, httpStatus: Int(response.status.code)) }
            return data
        }
        let certificate = try await exchange(url: "https://s.mzstatic.com/sap/setupCert.plist", key: "sign-sap-setup-cert", stage: .sapCertificate)
        let handshake = try SAPHandshake(certificate: certificate)
        let reply = try await exchange(
            url: "https://fpinit.itunes.apple.com/v1/signSapSetup/legacy", payload: handshake.request, key: "sign-sap-setup-buffer", stage: .sapSetup,
        )
        return try SAPSigner(session: handshake.complete(reply))
    }
}
