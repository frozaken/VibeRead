import Foundation
import AVFoundation
import Combine

/// Local macOS text-to-speech. Text never leaves this Mac.
@MainActor
final class InstantTTSService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = InstantTTSService()

    @Published var isSpeaking = false
    @Published var isPaused = false
    @Published var isLoading = false
    @Published var currentText: String?
    @Published var error: Error?
    @Published var currentChunk = 0
    @Published var totalChunks = 0
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isSpeedBoosted = false
    @Published var isPreviewPlaying = false
    @Published var previewingVoiceId: String?

    var currentPlaybackRate: Float {
        isSpeedBoosted ? Float(AppSettings.shared.speedBoostMultiplier) : 1
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVPlayer?
    private var playerObserver: Any?
    private var timeObserver: Any?
    private var progressTimer: Timer?
    private var isPreviewUtterance = false

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Local voices

    static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .sorted {
                if $0.language == $1.language { return $0.name < $1.name }
                return $0.language < $1.language
            }
    }

    func previewVoice(
        voiceId: String,
        text: String = "Hello! This is how I sound when reading for you."
    ) {
        stopPreview()
        stop()
        isPreviewPlaying = true
        previewingVoiceId = voiceId
        isPreviewUtterance = true
        synthesizer.speak(makeUtterance(text: text, voiceId: voiceId))
    }

    func stopPreview() {
        guard isPreviewPlaying || isPreviewUtterance else { return }
        synthesizer.stopSpeaking(at: .immediate)
        isPreviewPlaying = false
        previewingVoiceId = nil
        isPreviewUtterance = false
    }

    // MARK: - Main entry point

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        stop()
        currentText = trimmed
        currentChunk = 1
        totalChunks = 1
        duration = estimatedDuration(for: trimmed)
        currentTime = 0
        isLoading = false
        isPaused = false
        isSpeaking = true
        isPreviewUtterance = false

        synthesizer.speak(makeUtterance(text: trimmed, voiceId: AppSettings.shared.preferredVoiceId))
        startProgressTimer()
    }

    private func makeUtterance(text: String, voiceId: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceId)
        let speed = Float(AppSettings.shared.voiceSpeed) * currentPlaybackRate
        utterance.rate = min(
            AVSpeechUtteranceMaximumSpeechRate,
            max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * speed)
        )
        return utterance
    }

    private func estimatedDuration(for text: String) -> TimeInterval {
        let words = max(1, text.split(whereSeparator: { $0.isWhitespace }).count)
        let speed = max(0.5, AppSettings.shared.voiceSpeed * Double(currentPlaybackRate))
        return Double(words) / (175 * speed) * 60
    }

    // MARK: - Playback control

    func pause() {
        guard isSpeaking, !isPaused else { return }
        if player != nil {
            player?.pause()
        } else {
            synthesizer.pauseSpeaking(at: .word)
        }
        isPaused = true
    }

    func resume() {
        guard isPaused else { return }
        if player != nil {
            player?.play()
            player?.rate = currentPlaybackRate
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
        if let player {
            player.rate = isPaused ? 0 : currentPlaybackRate
            return
        }

        // AVSpeechSynthesizer cannot change rate mid-utterance. Restarting is
        // explicit and predictable, while keeping all processing local.
        if let text = currentText, isSpeaking {
            speak(text)
        }
    }

    func stop() {
        stopProgressTimer()
        cleanupPlayerObservers()
        synthesizer.stopSpeaking(at: .immediate)
        player?.pause()
        player = nil
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

    // MARK: - Local/explicit audio file playback compatibility

    func playURL(_ url: URL) {
        stop()
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        playerObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.finishPlayback() }
        }
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = time.seconds
                if let item = self.player?.currentItem, item.duration.isNumeric {
                    self.duration = item.duration.seconds
                }
            }
        }
        isSpeaking = true
        player?.play()
        player?.rate = currentPlaybackRate
    }

    private func cleanupPlayerObservers() {
        if let playerObserver {
            NotificationCenter.default.removeObserver(playerObserver)
            self.playerObserver = nil
        }
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isSpeaking, !self.isPaused else { return }
                self.currentTime = min(self.duration, self.currentTime + 0.25)
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func finishPlayback() {
        stopProgressTimer()
        cleanupPlayerObservers()
        player = nil
        isSpeaking = false
        isPaused = false
        isLoading = false
        isPreviewPlaying = false
        previewingVoiceId = nil
        isPreviewUtterance = false
        currentText = nil
        currentTime = 0
        duration = 0
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.finishPlayback() }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            if self.isPreviewUtterance {
                self.isPreviewPlaying = false
                self.previewingVoiceId = nil
                self.isPreviewUtterance = false
            }
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
