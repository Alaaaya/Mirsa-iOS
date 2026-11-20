import SwiftUI
import AVFoundation
import CryptoKit

enum ChatVoiceRules {
    static let maxBytes = 5 * 1024 * 1024
    static let maxDuration: TimeInterval = 300
    static func clock(_ time: TimeInterval) -> String {
        let value = max(0, Int(time))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
    static func verify(_ data: Data, meta: ChatAttachmentMeta?) throws {
        let bad = ChatAttachmentError(status: 422, code: "attachment_integrity")
        guard let meta, meta.kind == "audio", meta.mime == "audio/mp4",
              !data.isEmpty, data.count <= maxBytes, meta.size == Int64(data.count),
              let sha = meta.sha256, sha.count == 64,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == sha.lowercased(),
              data.count >= 12, String(data: data[4..<8], encoding: .ascii) == "ftyp" else { throw bad }
    }
}

enum ChatVoiceText {
    private static func pick(_ en: String, _ ar: String, _ de: String, _ kmr: String, _ ckb: String) -> String {
        switch AppLanguageStore.shared.current {
        case .english: return en
        case .arabic: return ar
        case .german: return de
        case .kurmanji: return kmr
        case .sorani: return ckb
        }
    }
    static var record: String { pick("Record voice message", "سجّل رسالة صوتية", "Sprachnachricht aufnehmen", "Peyama dengî tomar bike", "نامەی دەنگی تۆمار بکە") }
    static var recording: String { pick("Voice recording", "تسجيل صوتي", "Sprachaufnahme", "Tomara dengî", "تۆمارکردنی دەنگ") }
    static var discard: String { pick("Discard recording", "احذف التسجيل", "Aufnahme verwerfen", "Tomarê jê bibe", "تۆمارەکە بسڕەوە") }
    static var play: String { pick("Play voice message", "شغّل الرسالة الصوتية", "Sprachnachricht abspielen", "Peyama dengî bilîze", "نامەی دەنگی لێبدە") }
    static var pause: String { pick("Pause voice message", "وقّف الصوت", "Wiedergabe pausieren", "Deng rawestîne", "دەنگ بوەستێنە") }
    static var permission: String { pick("Allow microphone access in Settings to record a voice message.", "اسمح للميكروفون من الإعدادات لتسجّل رسالة صوتية.", "Erlaube den Mikrofonzugriff in den Einstellungen, um eine Sprachnachricht aufzunehmen.", "Di Mîhengan de destûra mîkrofonê bide da ku peyameke dengî tomar bikî.", "لە ڕێکخستنەکان ڕێگە بە مایکرۆفۆن بدە بۆ تۆمارکردنی نامەی دەنگی.") }
    static var failed: String { pick("Couldn't use the recording. Try again.", "ما زبط التسجيل. جرّب مرة تانية.", "Die Aufnahme konnte nicht verwendet werden. Versuche es erneut.", "Tomar nehat bikaranîn. Dîsa biceribîne.", "تۆمارەکە بەکارنەهات. دووبارە هەوڵ بدەرەوە.") }
    static var queued: String { pick("Voice message awaiting review", "الرسالة الصوتية بانتظار المراجعة", "Sprachnachricht wartet auf Prüfung", "Peyama dengî li benda nirxandinê ye", "نامەی دەنگی چاوەڕێی پێداچوونەوەیە") }
}

/// Records locally. No speech recognition, model, transcription, or third-party audio service.
@MainActor final class ChatVoiceRecorder: ObservableObject {
    @Published private(set) var hasRecording = false
    @Published private(set) var requesting = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0.05, count: 36)
    @Published var error: String?
    private var recorder: AVAudioRecorder?
    private var url: URL?
    private var timer: Timer?
    private var generation = UUID()
    private var interruption: NSObjectProtocol?

    init() {
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pause() }
        }
        #if DEBUG
        if ForgeChatStore.fixture && ProcessInfo.processInfo.arguments.contains("-MirsaVoiceRecordingFixture") {
            hasRecording = true; elapsed = 1
            levels = (0..<36).map { $0 < 26 ? 0.05 : CGFloat([0.2, 0.6, 0.9, 0.5, 0.75, 0.35, 0.5, 0.15, 0.08, 0.05][$0 - 26]) }
        }
        #endif
    }

    func start() async {
        guard !requesting, !hasRecording else { return }
        requesting = true; error = nil
        let ticket = UUID(); generation = ticket
        defer { requesting = false }
        guard await AVAudioApplication.requestRecordPermission() else { error = ChatVoiceText.permission; return }
        guard generation == ticket else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("mirsa-voice-\(UUID().uuidString).m4a")
            url = file
            let next = try AVAudioRecorder(url: file, settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 24_000,
                AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 48_000
            ])
            recorder = next
            next.isMeteringEnabled = true
            guard next.prepareToRecord(), next.record() else { throw ChatAttachmentError.network }
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: file.path)
            hasRecording = true; elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } catch { discard(); self.error = ChatVoiceText.failed }
    }

    private func tick() {
        guard let recorder, recorder.isRecording else { pause(); return }
        recorder.updateMeters(); elapsed = recorder.currentTime
        levels.removeFirst()
        levels.append(CGFloat(max(0.05, min(1, pow(10, Double(recorder.averagePower(forChannel: 0)) / 32)))))
        if elapsed >= ChatVoiceRules.maxDuration { pause() }
    }

    /// Interrupt/background keeps the unsent recording available for Send or Delete.
    func pause() {
        generation = UUID()
        if let recorder { elapsed = max(elapsed, recorder.currentTime); recorder.stop() }
        recorder = nil; timer?.invalidate(); timer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func finish() throws -> ChatAttachmentPayload {
        pause()
        guard let url, elapsed >= 0.25 else { throw ChatAttachmentError(status: 422, code: "attachment_audio") }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty, data.count <= ChatVoiceRules.maxBytes else { throw ChatAttachmentError(status: 422, code: "attachment_size") }
        return .audio(data: data, name: "voice.m4a", durationMS: min(300_000, max(1, Int(elapsed * 1000))))
    }

    func discard() {
        pause()
        if let url { try? FileManager.default.removeItem(at: url) }
        url = nil; hasRecording = false; elapsed = 0
        levels = Array(repeating: 0.05, count: 36)
    }

    deinit {
        timer?.invalidate(); recorder?.stop()
        if let interruption { NotificationCenter.default.removeObserver(interruption) }
        if let url { try? FileManager.default.removeItem(at: url) }
    }
}

struct ChatVoiceWaveform: View {
    var levels: [CGFloat]
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 3) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule().fill(Color(red: 0.43, green: 0.60, blue: 0.84))
                        .frame(width: max(2, (geo.size.width - CGFloat(max(0, levels.count - 1)) * 3) / CGFloat(max(1, levels.count))), height: max(3, 24 * level))
                }
            }.frame(height: geo.size.height)
        }.frame(height: 26).accessibilityHidden(true)
    }
}

@MainActor final class ChatVoicePlayer: ObservableObject {
    @Published private(set) var playing = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var loading = false
    @Published var error: String?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    func toggle(meta: ChatAttachmentMeta, threadID: UUID) async {
        guard !loading, !meta.isExpired() else { return }
        if playing { stop(); return }
        loading = true; error = nil
        defer { loading = false }
        do {
            if player == nil {
                let data: Data
                #if DEBUG
                if ForgeChatStore.fixture, let file = Bundle.main.url(forResource: "voice-fixture", withExtension: "m4a") {
                    data = try Data(contentsOf: file)
                    try ChatVoiceRules.verify(data, meta: meta)
                } else {
                    guard case .bytes(let bytes, let mime) = try await AttachmentUploader.shared.read(meta.id, threadID: threadID, expected: meta), mime == "audio/mp4" else { throw ChatAttachmentError.network }
                    data = bytes
                }
                #else
                guard case .bytes(let bytes, let mime) = try await AttachmentUploader.shared.read(meta.id, threadID: threadID, expected: meta), mime == "audio/mp4" else { throw ChatAttachmentError.network }
                data = bytes
                #endif
                player = try AVAudioPlayer(data: data)
            }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            guard let player else { throw ChatAttachmentError.network }
            duration = player.duration
            guard duration > 0, duration <= ChatVoiceRules.maxDuration + 1 else { throw ChatAttachmentError.network }
            if player.currentTime >= duration { player.currentTime = 0 }
            guard player.play() else { throw ChatAttachmentError.network }
            playing = true
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.position = self.player?.currentTime ?? 0
                    if self.player?.isPlaying != true { self.stop() }
                }
            }
        } catch { stop(); self.error = ChatVoiceText.failed }
    }
    func stop() {
        player?.pause(); playing = false; timer?.invalidate(); timer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    deinit { timer?.invalidate(); player?.stop() }
}

struct ChatVoiceBubble: View {
    let meta: ChatAttachmentMeta
    let threadID: UUID
    @StateObject private var player = ChatVoicePlayer()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 12) {
                Button { Task { await player.toggle(meta: meta, threadID: threadID) } } label: {
                    Group {
                        if player.loading { ProgressView() }
                        else { Image(systemName: player.playing ? "pause.fill" : "play.fill") }
                    }.frame(width: 44, height: 44)
                }.disabled(meta.isExpired()).accessibilityLabel(player.playing ? ChatVoiceText.pause : ChatVoiceText.play)
                    .accessibilityIdentifier("chat-voice-play")
                ChatVoiceWaveform(levels: (0..<28).map { CGFloat([0.15, 0.35, 0.7, 0.5, 0.9, 0.4, 0.6][$0 % 7]) })
                Text(ChatVoiceRules.clock(player.playing ? player.position : player.duration > 0 ? player.duration : Double(meta.durationMS ?? 0) / 1000)).font(.caption.monospacedDigit())
            }
            if meta.isExpired() { Text(ChatAttachmentText.unavailable).font(.caption) }
            if let error = player.error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(10).frame(maxWidth: 280)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityIdentifier("chat-voice-bubble")
        .onDisappear { player.stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { player.stop() } }
    }
}


// Kept out of production flows. The fixture is a two-second sine tone, not user audio.
#if DEBUG
enum ChatVoiceFixture {
    static func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
#endif
