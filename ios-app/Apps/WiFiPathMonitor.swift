import Foundation
import Network

/// What the system says about the link Apple ID installs would use.
enum WiFiPathState: Equatable { case unknown, wifi, notWifi }

enum WiFiGuardVerdict: Equatable { case allow, needWiFi, undetermined }

enum WiFiPathPolicy {
    /// A usable path with a Wi-Fi interface in use or available counts as Wi-Fi.
    /// "Available" matters because LocalDevVPN's utun can hide Wi-Fi from "in use".
    static func state(satisfied: Bool, usesWiFi: Bool, wifiAvailable: Bool) -> WiFiPathState {
        satisfied && (usesWiFi || wifiAvailable) ? .wifi : .notWifi
    }

    /// NWPathMonitor is the only authority. A known non-Wi-Fi path blocks.
    /// Unknown (no update yet) never reads as cellular and never allows: the
    /// caller asks the user to retry. There is deliberately no interface-name fallback.
    static func verdict(path: WiFiPathState) -> WiFiGuardVerdict {
        switch path {
        case .wifi: return .allow
        case .notWifi: return .needWiFi
        case .unknown: return .undetermined
        }
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
                                            usesWiFi: path.usesInterfaceType(.wifi),
                                            wifiAvailable: path.availableInterfaces.contains { $0.type == .wifi })
            Task { @MainActor in self?.state = next }
        }
        monitor.start(queue: DispatchQueue(label: "mirsa.wifi-path", qos: .utility))
    }

    /// Waits (up to timeout) for the first real path update instead of guessing.
    func resolve(timeoutMs: Int = 3_000) async -> WiFiPathState {
        start()
        var waited = 0
        while state == .unknown && waited < timeoutMs {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 100
        }
        return state
    }
}
