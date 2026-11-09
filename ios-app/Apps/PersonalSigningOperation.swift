import Foundation
import SwiftUI
import UIKit

/// Shared operation lifetime is independent of the project view's navigation.
@MainActor
final class PersonalSigningOperation: ObservableObject {
    static let shared = PersonalSigningOperation()
    enum Stage: String {
        case preparing, signing, packaging, uploading, serving, connecting, installing, handedOff, completed, failed
        var order: Int {
            switch self {
            case .preparing: return 0
            case .signing: return 1
            case .packaging: return 2
            case .uploading, .serving: return 3
            case .connecting: return 4
            case .installing: return 5
            case .handedOff, .completed, .failed: return 6
            }
        }
    }
    struct State {
        let id: UUID
        let projectID: UUID
        var stage: Stage = .preparing
        var fraction: Double?
        var completedUnits: UInt64 = 0
        var totalUnits: UInt64 = 0
        /// Set only when the local route was tried/skipped and upload was used instead.
        var fallbackReason: OTAUploadReason?
        /// Overall weighted work completion, not a prediction of elapsed time.
        /// Within a stage use measured units/bytes only. A pending installer never reaches 100%.
        var overallFraction: Double {
            let measured = fraction.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil } ?? 0
            switch stage {
            case .preparing: return 0
            case .signing: return 0.10 + measured * 0.55
            case .packaging: return 0.65 + measured * 0.10
            case .uploading: return 0.75 + measured * 0.20
            case .serving: return 0.95
            case .connecting: return 0.95
            case .installing: return 0.97 + min(0.99, measured) * 0.02
            case .handedOff: return 0.99
            case .completed: return 1
            case .failed: return 0
            }
        }
        var running = true
        var backgroundExpired = false
        var result: PersonalCertificateSigner.Result?
        var error: String?
        // OTA has no installation-completion callback. Once handed off, the
        // local operation is over, not an indefinitely running 99% progress bar.
        var showsInlineProgress: Bool { running }
        var shouldPresentResultAlert: Bool { !running && stage != .handedOff }

        /// Main-actor callbacks can be enqueued out of order. Do not regress a
        /// measured stage or republish unchanged progress on every backend tick.
        @discardableResult
        mutating func apply(_ event: PersonalSigningEvent) -> Bool {
            guard running, event.stage.order >= stage.order else { return false }
            let sameStage = stage == event.stage
            let nextFraction: Double?
            if sameStage, let current = fraction {
                nextFraction = max(current, event.fraction.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil } ?? current)
            } else { nextFraction = event.fraction.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil } }
            let nextCompleted = sameStage ? max(completedUnits, event.completed) : event.completed
            let nextReason = event.fallbackReason ?? fallbackReason
            guard stage != event.stage || fraction != nextFraction || nextReason != fallbackReason ||
                    completedUnits != nextCompleted || totalUnits != event.total else { return false }
            stage = event.stage; fraction = nextFraction; fallbackReason = nextReason
            completedUnits = nextCompleted; totalUnits = event.total
            return true
        }
    }
    @Published private(set) var state: State?
    init(initialState: State? = nil) { state = initialState }
    private var backgroundID: UIBackgroundTaskIdentifier = .invalid
    private var control: PersonalSigningControl?
    private var activityID: String?
    var running: Bool { state?.running == true }

    func start(projectID: UUID, title: String, input: URL, material: PersonalIdentityVault.Material,
               pairingPath: String, options: PersonalProjectOptions) {
        guard !running else { return }
        if let previous = state?.result?.url {
            try? FileManager.default.removeItem(at: previous.deletingLastPathComponent())
        }
        let id = UUID()
        let control = PersonalSigningControl()
        self.control = control
        lastActivityStage = nil
        state = State(id: id, projectID: projectID)
        let operation = MirsaOperationProgress.shared.begin(appID: projectID.uuidString, phase: .preparing)
        MirsaOperationProgress.shared.update(operation, phase: .preparing, fraction: 0)
        activityID = MirsaInstallActivity.shared.begin(title: title, phase: .preparing)
        backgroundID = UIApplication.shared.beginBackgroundTask(withName: "Mirsa signing and installation") { [weak self] in
            // UIKit invokes this handler on the main thread. End the grant
            // before the expiration handler returns, not in a later queued task.
            MainActor.assumeIsolated { self?.expire(id: id) }
        }
        // Deliberately NOT attached to SwiftUI .task; leaving the screen cannot cancel it.
        Task {
            do {
                do {
                    _ = try await CertificateOTA.install(source: input, sourceIsArchive: true, control: control, material: material, options: options, projectID: projectID,
                        signingProgress: { event in self.receive(event, id: id, operation: operation) })
                    self.state?.running = false
                    self.state?.stage = .handedOff
                    self.state?.error = nil
                    if let activityID = self.activityID, MirsaInstallActivity.shared.operationID == activityID {
                        MirsaInstallActivity.shared.handoffToInstaller()
                    }
                    self.activityID = nil
                    MirsaOperationProgress.shared.finish(operation)
                    self.endBackgroundTime()
                    self.control = nil
                    return
                }
            } catch {
                guard self.state?.id == id else { return }
                self.state?.stage = .failed
                self.state?.fraction = nil
                self.state?.error = error.localizedDescription
                self.state?.running = false
                self.finishActivity(success: false)
                MirsaCompletionFeedback.shared.finish(operationID: operation, outcome: MirsaCompletionFeedback.outcome(for: error))
            }
            MirsaOperationProgress.shared.finish(operation)
            self.endBackgroundTime()
            self.control = nil
        }
    }

    private func receive(_ event: PersonalSigningEvent, id: UUID, operation: UUID) {
        guard var next = state, next.id == id, next.apply(event) else { return }
        state = next
        let phase: MirsaOperationProgress.Phase
        let activity: MirsaInstallActivity.Phase
        switch event.stage {
        case .signing: phase = .signing; activity = .signing
        case .uploading, .serving, .installing, .connecting, .handedOff: phase = .installing; activity = .installing
        default: phase = .preparing; activity = .preparing
        }
        MirsaOperationProgress.shared.update(operation, phase: phase, fraction: next.overallFraction, stageLabel: PersonalSigningLabels.stage(next.stage))
        // Do not overwrite another download's activity if that operation replaced ours.
        guard let activityID, MirsaInstallActivity.shared.operationID == activityID else { return }
        // Reset percentage only at a real stage transition.
        if lastActivityStage != event.stage {
            lastActivityStage = event.stage
            MirsaInstallActivity.shared.setPhase(activity)
        }
        MirsaInstallActivity.shared.updateProgress(next.overallFraction)
    }
    private func finishActivity(success: Bool) {
        if let activityID, MirsaInstallActivity.shared.operationID == activityID {
            MirsaInstallActivity.shared.finish(success: success)
        }
        activityID = nil
    }
    private var lastActivityStage: Stage?
    private func expire(id: UUID) {
        guard state?.id == id, running else { return }
        control?.cancel()
        state?.backgroundExpired = true
        // No promise of unlimited execution. Current blocking install may settle only
        // after foregrounding; we never announce failure/success before its actual result.
        endBackgroundTime()
    }
    private func endBackgroundTime() {
        guard backgroundID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundID)
        backgroundID = .invalid
    }
}

struct PersonalSigningEvent {
    static func installation(_ fraction: Double, stage: String) -> PersonalSigningEvent? {
        guard stage == "Installing", fraction.isFinite else { return nil }
        return PersonalSigningEvent(stage: .installing, fraction: min(0.99, max(0, fraction)))
    }
    static func signing(completed: UInt64, total: UInt64) -> PersonalSigningEvent {
        PersonalSigningEvent(stage: .signing, fraction: total > 0 ? min(1, Double(completed) / Double(total)) : nil,
                             completed: completed, total: total)
    }
    let stage: PersonalSigningOperation.Stage
    var fraction: Double? = nil
    var completed: UInt64 = 0
    var total: UInt64 = 0
    var fallbackReason: OTAUploadReason? = nil
}
/// Shared only for cooperative cancellation checks, never secrets or file paths.
final class PersonalSigningControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func checkpoint() throws {
        if isCancelled { throw SideloadError.message("انتهى وقت الخلفية. افتح Mirsa وجرّب التوقيع من جديد.") }
    }
}

struct PersonalSigningProgressView: View {
    let state: PersonalSigningOperation.State
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: state.stage == .installing ? "iphone.and.arrow.forward" : "signature")
                Text(label).fontWeight(.semibold)
                Spacer()
                Text("\(Int(state.overallFraction * 100))%").monospacedDigit().fontWeight(.bold)
            }
            ProgressView(value: state.overallFraction).tint(.green)
                .accessibilityValue("\(Int(state.overallFraction * 100))%")
            Text(PersonalSigningLabels.weighted).font(.caption2).foregroundStyle(.secondary)
            if state.stage == .signing, state.totalUnits > 0 {
                Text(personalText("Signed bundles", "الحزم الموقّعة") + " \(state.completedUnits)/\(state.totalUnits)").font(.caption).foregroundStyle(.secondary)
            }
            if let reason = state.fallbackReason {
                Text(personalText("Local install unavailable, using upload instead. ", "التثبيت المحلي مو متاح، استخدمت الرفع. ") + personalText(reason.english, reason.arabic))
                    .font(.caption).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("personalSigningFallbackReason")
            }
            if state.backgroundExpired {
                Text(personalText("Background time ended. Keep Mirsa open to see the result.",
                    "خلص وقت الخلفية. افتح Mirsa لتشوف النتيجة.")).font(.caption).foregroundStyle(.orange)
            }
        }.accessibilityIdentifier("personalSigningProgress")
    }
    private var label: String { PersonalSigningLabels.stage(state.stage) }
}

/// Explicit translations keep the new progress surface available in all four app languages.
enum PersonalSigningLabels {
    static func text(_ en: String, _ ar: String, _ ckb: String, _ kmr: String, language: AppLanguage = AppLanguageStore.snapshot) -> String {
        switch language {
        case .english: return en
        case .arabic: return ar
        case .sorani: return ckb
        case .kurmanji: return kmr
        }
    }
    static var weighted: String { text("Overall stage progress; measured units/bytes when available", "تقدّم المراحل الإجمالي؛ حسب الحزم أو البايتات لما تتوفر", "پێشکەوتنی گشتی قۆناغەکان؛ بە یەکە یان بایت کاتێک بەردەستە", "Pêşveçûna giştî ya qonaxan; bi yekeyan an baytan dema berdest bin") }
    static func stage(_ stage: PersonalSigningOperation.Stage, language: AppLanguage = AppLanguageStore.snapshot) -> String {
        switch stage {
        case .preparing: return text("Preparing", "تجهيز", "ئامادەکردن", "Amadekirin", language: language)
        case .signing: return text("Signing", "توقيع", "واژۆکردن", "Îmzekirin", language: language)
        case .packaging: return text("Archiving signed IPA", "ضغط الـ IPA الموقّع", "ئەرشیفکردنی IPAی واژۆکراو", "Arşîvkirina IPA ya îmzekirî", language: language)
        case .uploading: return text("Uploading signed IPA", "رفع الـ IPA الموقّع", "بارکردنی IPAی واژۆکراو", "Barkirina IPA ya îmzekirî", language: language)
        case .serving: return text("Serving signed IPA from this device", "تقديم الـ IPA الموقّع من هالجهاز", "پێشکەشکردنی IPAی واژۆکراو لەم ئامێرە", "Pêşkêşkirina IPA ya îmzekirî ji vê cihazê", language: language)
        case .connecting: return text("Opening iOS installer", "فتح مثبّت iOS", "کردنەوەی دامەزرێنەری iOS", "Vekirina sazkera iOS", language: language)
        case .installing: return text("Installing", "تثبيت", "دامەزراندن", "Sazkirin", language: language)
        case .handedOff: return text("Waiting for system installation", "في انتظار تثبيت النظام", "چاوەڕێی دامەزراندنی سیستەم", "Li benda sazkirina pergalê", language: language)
        case .completed: return text("Installation confirmed", "تم تأكيد التثبيت", "دامەزراندن پشتڕاست کرایەوە", "Sazkirin hate piştrastkirin", language: language)
        case .failed: return text("Not completed", "ما اكتملت العملية", "تەواو نەبوو", "Temam nebû", language: language)
        }
    }
}
