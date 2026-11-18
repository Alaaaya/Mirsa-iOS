import ActivityKit
import Foundation
import UIKit

/// Local-only updates. iOS may throttle them; no push server or keep-alive is used.
@MainActor
final class MirsaInstallActivity {
    typealias Phase = MirsaDownloadAttributes.Phase
    typealias State = MirsaDownloadAttributes.ContentState
    static let shared = MirsaInstallActivity()

    private var activity: Activity<MirsaDownloadAttributes>?
    var operationID: String? { activity?.attributes.operationID }
    private var endedIDs = Set<String>()
    private var state: State?
    private var lastProgressUpdate = Date.distantPast
    private var lastPercent = -1
    private var updates: Task<Void, Never>?

    /// Returns an opaque ID that may be attached to a background URLSession task.
    @discardableResult
    func begin(title: String, phase: Phase = .downloading) -> String? {
        cancel()
        guard UIApplication.shared.applicationState == .active,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }
        let initial = State(title: String(title.prefix(100)), phase: phase,
                            progress: nil, receivedBytes: 0, expectedBytes: 0, isArabic: L.isArabic)
        do {
            let new = try Activity.request(attributes: MirsaDownloadAttributes(operationID: UUID().uuidString),
                                           content: ActivityContent(state: initial, staleDate: Date().addingTimeInterval(90)),
                                           pushType: nil)
            activity = new
            state = initial
            lastProgressUpdate = .distantPast
            lastPercent = -1
            return new.attributes.operationID
        } catch {
            // Live Activities are optional. Failure must never interrupt an install.
            return nil
        }
    }

    /// Reattach after an OS background relaunch without starting a new activity.
    func restore(operationID: String?) {
        guard let operationID, !endedIDs.contains(operationID) else { return }
        guard activity == nil || activity?.attributes.operationID == operationID else { return }
        if activity?.attributes.operationID == operationID { return }
        guard let existing = Activity<MirsaDownloadAttributes>.activities.first(where: {
            $0.attributes.operationID == operationID && ($0.activityState == .active || $0.activityState == .stale)
        }) else { return }
        activity = existing
        state = existing.content.state
    }

    func setPhase(_ phase: Phase, title: String? = nil) {
        if activity == nil, let title { begin(title: title, phase: phase) }
        guard var value = state else { return }
        value.phase = phase
        value.progress = nil
        if let title { value.title = String(title.prefix(100)) }
        state = value
        // Import/editor readiness is terminal too, not a running install. Previously
        // these callers only updated the widget, leaving it active indefinitely.
        switch phase {
        case .ready, .completed, .failed:
            end(phase: phase, immediate: false)
        case .cancelled:
            end(phase: phase, immediate: true)
        default:
            publish(value)
        }
    }

    /// Sweep OS-retained activities even when our in-memory reference was lost.
    /// Background launch preserves a fresh download for URLSession reattachment.
    /// Foreground also removes orphans and already-ended lock-screen summaries.
    func reconcileActivities(foreground: Bool) {
        for existing in Activity<MirsaDownloadAttributes>.activities {
            let current = existing.attributes.operationID == operationID
            let terminal: Bool
            switch existing.content.state.phase {
            case .ready, .completed, .failed, .cancelled: terminal = true
            default: terminal = false
            }
            let expired = existing.content.staleDate.map { $0 <= Date() } ?? false
            guard terminal || existing.activityState == .stale || expired ||
                    (foreground && (!current || existing.activityState == .ended)) else { continue }
            endedIDs.insert(existing.attributes.operationID)
            if current {
                activity = nil
                state = nil
            }
            var finalState = existing.content.state
            if !terminal { finalState.phase = .cancelled; finalState.progress = nil }
            let previous = updates
            updates = Task {
                await previous?.value
                await existing.end(ActivityContent(state: finalState, staleDate: Date()),
                                   dismissalPolicy: .immediate)
            }
        }
    }

    func updateBytes(received: Int64, expected: Int64, operationID: String?) {
        restore(operationID: operationID)
        // Ignore callbacks from old URLSession tasks after another install starts.
        guard let operationID, activity?.attributes.operationID == operationID,
              var value = state, value.phase == .downloading else { return }
        value.receivedBytes = max(0, received)
        value.expectedBytes = max(0, expected)
        value.progress = expected > 0 ? min(1, max(0, Double(received) / Double(expected))) : nil
        state = value
        publishProgress(value)
    }

    /// Install progress is independent from the download percentage.
    func updateProgress(_ fraction: Double) {
        guard fraction.isFinite, var value = state else { return }
        value.progress = min(1, max(0, fraction))
        state = value
        publishProgress(value)
    }

    func downloadFinished(operationID: String?, continuing: Bool, success: Bool) {
        restore(operationID: operationID)
        guard let operationID, activity?.attributes.operationID == operationID else { return }
        if success && continuing { setPhase(.preparing) }
        else if success { end(phase: .ready, immediate: false) }
        else { finish(success: false) }
    }

    /// OTA opening is only a handoff. End without the installed/100% completion badge.
    func handoffToInstaller() { end(phase: .installing, immediate: true, progress: 0.99) }

    func finish(success: Bool) { end(phase: success ? .completed : .failed, immediate: false) }
    func cancel() { end(phase: .cancelled, immediate: true) }

    /// Await before giving iOS a background-session completion handler.
    func flush() async { await updates?.value }

    private func publishProgress(_ value: State) {
        let percent = value.progress.map { Int($0 * 100) } ?? -1
        let elapsed = Date().timeIntervalSince(lastProgressUpdate)
        guard elapsed >= 1, percent != lastPercent || elapsed >= 15 else { return }
        lastProgressUpdate = Date()
        lastPercent = percent
        publish(value)
    }

    /// Serializes async ActivityKit calls so a queued percent cannot overwrite a final state.
    private func publish(_ value: State) {
        guard let activity else { return }
        let previous = updates
        updates = Task {
            await previous?.value
            await activity.update(ActivityContent(state: value, staleDate: Date().addingTimeInterval(90)))
        }
    }

    private func end(phase: Phase, immediate: Bool, progress: Double? = nil) {
        guard let activity, var finalState = state else { return }
        endedIDs.insert(activity.attributes.operationID)
        finalState.phase = phase
        finalState.progress = progress ?? (phase == .completed || phase == .ready ? 1 : nil)
        let previous = updates
        updates = Task {
            await previous?.value
            let dismissAt = Date().addingTimeInterval(5)
            await activity.end(ActivityContent(state: finalState, staleDate: dismissAt),
                               dismissalPolicy: immediate ? .immediate : .after(dismissAt))
        }
        self.activity = nil
        state = nil
    }
}
