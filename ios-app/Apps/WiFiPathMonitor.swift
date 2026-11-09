import Foundation
import Network

/// What the system says about the link Apple ID installs would use.
enum WiFiPathState: Equatable { case unknown, wifi, notWifi }

enum WiFiGuardVerdict: Equatable { case allow, needWiFi, undetermined }

enum WiFiPathPolicy {
    static func state(satisfied: Bool, usesWiFi: Bool) -> WiFiPathState {
        satisfied && usesWiFi ? .wifi : .notWifi
    }

    /// Unknown never reads as cellular. Either signal saying Wi-Fi is enough,
    /// because a VPN can hide the underlying interface from one of them.
    static func verdict(path: WiFiPathState, en0HasAddress: Bool) -> WiFiGuardVerdict {
        if path == .wifi || en0HasAddress { return .allow }
        return path == .unknown ? .undetermined : .needWiFi
    }
}

@MainActor
final class WiFiPathMonitor {
    static let shared = WiFiPathMonitor()
    private let monitor = NWPathMonitor()
    private var started = false
    private(set) var state: WiFiPathState = .unknown

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let next = WiFiPathPolicy.state(satisfied: path.status == .satisfied,
                                            usesWiFi: path.usesInterfaceType(.wifi))
            Task { @MainActor in self?.state = next }
        }
        monitor.start(queue: DispatchQueue(label: "mirsa.wifi-path", qos: .utility))
    }

    /// Waits (up to timeout) for the first real path update instead of guessing.
    func resolve(timeoutMs: Int = 2_000) async -> WiFiPathState {
        start()
        var waited = 0
        while state == .unknown && waited < timeoutMs {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 100
        }
        return state
    }
}
