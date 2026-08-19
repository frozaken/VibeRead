import Foundation
import AVFoundation
import Combine

/// One read-aloud engine with an explicit local or ElevenLabs boundary.
/// No credential is read until the user asks to read, preview, or load voices.
@MainActor
final class InstantTTSService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = InstantTTSService()

    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var isLoading = false
    @Published private(set) var currentText: String?
    @Published var error: Error?
    @Published private(set) var currentChunk = 0
    @Published private(set) var totalChunks = 0
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isSpeedBoosted = false
    @Published private(set) var isPreviewPlaying = false
    @Published private(set) var previewingVoiceId: String?
    @Published private(set) var elevenLabsVoices: [ElevenLabsVoice] = []
    @Published private(set) var isLoadingVoices = false

    var currentPlaybackRate: Float {
        isSpeedBoosted ? Float(AppSettings.shared.speedBoostMultiplier) : 1
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let elevenLabsClient: ElevenLabsTTSClient
    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?
    private var playbackTask: Task<Void, Never>?
    private var playbackGeneration = UUID()
    private var isPreviewUtterance = false
    private let cachedVoicesKey = "elevenLabs.voices.v1"
    private let maximumChunkCharacters = 3_500

    init(elevenLabsClient: ElevenLabsTTSClient = ElevenLabsTTSClient()) {
        self.elevenLabsClient = elevenLabsClient
        super.init()
        synthesizer.delegate = self
        if let data = UserDefaults.standard.data(forKey: cachedVoicesKey),
           let voices = try? JSONDecoder().decode([ElevenLabsVoice].self, from: data) {
            elevenLabsVoices = voices
        }
    }

    static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().sorted {
            if $0.language == $1.language { return $0.name < $1.name }
            return $0.language < $1.language
        }
    }

    func refreshElevenLabsVoices() {
        guard !isLoadingVoices else { return }
        isLoadingVoices = true
        error = nil
        Task { [weak self] in
            guard let self else { return }
            do {
                let key = try AIProviderSettings.shared.elevenLabsAPIKeyForExplicitUse()
                let voices = try await elevenLabsClient.listVoices(apiKey: key)
                try Task.checkCancellation()
                self.elevenLabsVoices = voices
                self.isLoadingVoices = false
                if let data = try? JSONEncoder().encode(voices) {
                    UserDefaults.standard.set(data, forKey: self.cachedVoicesKey)
                }
                if !voices.contains(where: { $0.voiceID == AppSettings.shared.elevenLabsVoiceId }),
                   let first = voices.first {
                    AppSettings.shared.elevenLabsVoiceId = first.voiceID
                    AppSettings.shared.elevenLabsVoiceName = first.name
                }
            } catch is CancellationError {
                self.isLoadingVoices = false
            } catch {
                self.isLoadingVoices = false
                self.error = error
            }
        }
    }

    func previewVoice(
        voiceId: String,
        text: String = "Hello. This is how I sound when reading for you."
    ) {
        stopPreview()
        stop()
        isPreviewPlaying = true
        previewingVoiceId = voiceId

        if AppSettings.shared.readAloudProvider == .macOS {
            isPreviewUtterance = true
            synthesizer.speak(makeLocalUtterance(text: text, voiceId: voiceId))
            return
        }

        playbackTask = Task { [weak self] in
            guard let self else { return }
            do {
                let key = try AIProviderSettings.shared.elevenLabsAPIKeyForExplicitUse()
                let audio = try await elevenLabsClient.synthesize(
                    text: text,
                    voiceID: voiceId,
                    modelID: AppSettings.shared.elevenLabsTTSModel,
                    settings: elevenLabsSettings,
                    apiKey: key
                )
                try Task.checkCancellation()
                try self.startAudioPlayer(data: audio)
            } catch is CancellationError {
                self.stopPreview()
            } catch {
                self.stopPreview()
                self.error = error
            }
        }
    }

    func stopPreview() {
        guard isPreviewPlaying || isPreviewUtterance else { return }
        playbackTask?.cancel()
        playbackTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        synthesizer.stopSpeaking(at: .immediate)
        isPreviewPlaying = false
        previewingVoiceId = nil
        isPreviewUtterance = false
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stop()
        currentText = trimmed
        error = nil
        isPaused = false

        switch AppSettings.shared.readAloudProvider {
        case .macOS:
            currentChunk = 1
            totalChunks = 1
            duration = estimatedLocalDuration(for: trimmed)
            isSpeaking = true
            synthesizer.speak(
                makeLocalUtterance(text: trimmed, voiceId: AppSettings.shared.preferredVoiceId)
            )
            startProgressTimer()
        case .elevenLabs:
            startElevenLabsPlayback(trimmed)
        }
    }

    private func startElevenLabsPlayback(_ text: String) {
        let chunks = Self.splitIntoChunks(text, maximumCharacters: maximumChunkCharacters)
        guard !chunks.isEmpty else { return }
        totalChunks = chunks.count
        currentChunk = 0
        isLoading = true
        isSpeaking = true
        let generation = UUID()
        playbackGeneration = generation

        playbackTask = Task { [weak self] in
            guard let self else { return }
            do {
                let settings = AppSettings.shared
                let key = try AIProviderSettings.shared.elevenLabsAPIKeyForExplicitUse()
                let voiceID = settings.elevenLabsVoiceId
                let modelID = settings.elevenLabsTTSModel
                let voiceSettings = self.elevenLabsSettings
                var currentAudio = try await elevenLabsClient.synthesize(
                    text: chunks[0],
                    voiceID: voiceID,
                    modelID: modelID,
                    settings: voiceSettings,
                    apiKey: key
                )

                for index in chunks.indices {
                    try Task.checkCancellation()
                    guard self.playbackGeneration == generation else { return }
                    let nextTask: Task<Data, Error>? = index + 1 < chunks.count
                        ? Task {
                            try await self.elevenLabsClient.synthesize(
                                text: chunks[index + 1],
                                voiceID: voiceID,
                                modelID: modelID,
                                settings: voiceSettings,
                                apiKey: key
                            )
                        }
                        : nil

                    self.currentChunk = index + 1
                    self.isLoading = false
                    try await self.playAudioAndWait(currentAudio, generation: generation)
                    if let nextTask {
                        self.isLoading = true
                        currentAudio = try await withTaskCancellationHandler {
                            try await nextTask.value
                        } onCancel: {
                            nextTask.cancel()
                        }
                    }
                }
                guard self.playbackGeneration == generation else { return }
                self.finishPlayback()
            } catch is CancellationError {
                guard self.playbackGeneration == generation else { return }
                self.finishPlayback()
            } catch {
                guard self.playbackGeneration == generation else { return }
                self.finishPlayback()
                self.error = error
            }
        }
    }

    private var elevenLabsSettings: ElevenLabsVoiceSettings {
        let settings = AppSettings.shared
        return ElevenLabsVoiceSettings(
            stability: settings.voiceStability,
            similarityBoost: settings.voiceSimilarityBoost,
            style: settings.voiceStyle,
            useSpeakerBoost: settings.voiceSpeakerBoost,
            speed: settings.voiceSpeed
        )
    }

    private func playAudioAndWait(_ data: Data, generation: UUID) async throws {
        try startAudioPlayer(data: data)
        isSpeaking = true
        startProgressTimer()
        while playbackGeneration == generation {
            try Task.checkCancellation()
            if isPaused {
                try await Task.sleep(nanoseconds: 80_000_000)
                continue
            }
            guard audioPlayer?.isPlaying == true else { break }
            try await Task.sleep(nanoseconds: 80_000_000)
        }
        stopProgressTimer()
    }

    private func startAudioPlayer(data: Data) throws {
        audioPlayer?.stop()
        let player = try AVAudioPlayer(data: data)
        player.enableRate = true
        player.rate = currentPlaybackRate
        player.prepareToPlay()
        duration = player.duration
        currentTime = 0
        audioPlayer = player
        player.play()
    }

    private func makeLocalUtterance(text: String, voiceId: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        if !voiceId.isEmpty { utterance.voice = AVSpeechSynthesisVoice(identifier: voiceId) }
        if utterance.voice == nil {
            utterance.voice = AVSpeechSynthesisVoice(
                language: Locale.current.language.languageCode?.identifier ?? "en"
            )
        }
        let speed = Float(AppSettings.shared.voiceSpeed) * currentPlaybackRate
        utterance.rate = min(
            AVSpeechUtteranceMaximumSpeechRate,
            max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * speed)
        )
        return utterance
    }

    private func estimatedLocalDuration(for text: String) -> TimeInterval {
        let words = max(1, text.split(whereSeparator: { $0.isWhitespace }).count)
        let speed = max(0.5, AppSettings.shared.voiceSpeed * Double(currentPlaybackRate))
        return Double(words) / (175 * speed) * 60
    }

    nonisolated static func splitIntoChunks(_ text: String, maximumCharacters: Int) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maximumCharacters else { return trimmed.isEmpty ? [] : [trimmed] }
        var result: [String] = []
        var remainder = trimmed[...]
        while remainder.count > maximumCharacters {
            let hardEnd = remainder.index(remainder.startIndex, offsetBy: maximumCharacters)
            let candidate = remainder[..<hardEnd]
            let split = candidate.lastIndex(where: { ".!?\n".contains($0) })
                ?? candidate.lastIndex(where: { $0.isWhitespace })
                ?? hardEnd
            let chunk = remainder[..<split].trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty { result.append(chunk) }
            remainder = remainder[split...].drop(while: { $0.isWhitespace })
        }
        let final = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        if !final.isEmpty { result.append(final) }
        return result
    }

    func pause() {
        guard isSpeaking, !isPaused else { return }
        if let audioPlayer { audioPlayer.pause() }
        else { synthesizer.pauseSpeaking(at: .word) }
        isPaused = true
    }

    func resume() {
        guard isPaused else { return }
        if let audioPlayer {
            audioPlayer.play()
            audioPlayer.rate = currentPlaybackRate
        } else {
            synthesizer.continueSpeaking()
        }
        isPaused = false
    }

    func toggle() {
        if isPaused { resume() }
        else if isSpeaking { pause() }
    }

    func toggleSpeedBoost() {
        isSpeedBoosted.toggle()
        if let audioPlayer {
            audioPlayer.rate = currentPlaybackRate
        } else if let text = currentText, isSpeaking {
            speak(text)
        }
    }

    func stop() {
        playbackGeneration = UUID()
        playbackTask?.cancel()
        playbackTask = nil
        stopProgressTimer()
        synthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        audioPlayer = nil
        isSpeaking = false
        isPaused = false
        isLoading = false
        isPreviewPlaying = false
        previewingVoiceId = nil
        isPreviewUtterance = false
        currentText = nil
        error = nil
        currentChunk = 0
        totalChunks = 0
        currentTime = 0
        duration = 0
    }

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isSpeaking, !self.isPaused else { return }
                if let player = self.audioPlayer {
                    self.currentTime = player.currentTime
                    self.duration = player.duration
                } else {
                    self.currentTime = min(self.duration, self.currentTime + 0.2)
                }
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func finishPlayback() {
        stopProgressTimer()
        audioPlayer?.stop()
        audioPlayer = nil
        isSpeaking = false
        isPaused = false
        isLoading = false
        isPreviewPlaying = false
        previewingVoiceId = nil
        isPreviewUtterance = false
        currentText = nil
        currentTime = 0
        duration = 0
        playbackTask = nil
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            if self.isPreviewUtterance {
                self.isPreviewPlaying = false
                self.previewingVoiceId = nil
                self.isPreviewUtterance = false
            } else {
                self.finishPlayback()
            }
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isPreviewPlaying = false
            self.previewingVoiceId = nil
            self.isPreviewUtterance = false
        }
    }

    var remainingTime: TimeInterval { max(0, duration - currentTime) }

    func formatTime(_ time: TimeInterval, asRemaining: Bool = false) -> String {
        guard time.isFinite && !time.isNaN else { return "0:00" }
        let totalSeconds = Int(time)
        return String(
            format: "%@%d:%02d",
            asRemaining ? "-" : "",
            totalSeconds / 60,
            totalSeconds % 60
        )
    }
}
