import Foundation
import AppKit
import Combine

/// Orchestrates dictation: record -> transcribe -> paste
class DictationService: ObservableObject {
    static let shared = DictationService()

    /// Recording mode determines what happens after transcription
    enum RecordingMode {
        case normal      // Paste to current app (push-to-talk)
        case handsFree   // Click to start, click to send (paste to current app)
        case command     // Send to AI provider (ChatGPT, Claude, Perplexity)
    }

    /// Input mode for how recording is triggered
    enum InputMode {
        case pushToTalk   // Hold to record, release to transcribe
        case handsFree    // Click to start, click to send
    }

    enum State: Equatable {
        case idle
        case recording
        case recordingHandsFree  // Hands-free mode recording (green indicator)
        case recordingCommand  // Command mode recording (yellow indicator)
        case recordingWarning(message: String)  // Recording time limit warning
        case transcribing
        case transcribingHandsFree  // Hands-free mode transcribing
        case transcribingCommand  // Command mode transcribing
        case transcribingSlow  // Taking longer than expected
        case done
        case cancelled  // Shows undo option
        case cancelledWhileTranscribing  // Cancelled during transcription
        case error(String)
    }

    @Published var state: State = .idle
    @Published var lastResult: DictationResult?
    @Published var recordingDuration: TimeInterval = 0
    @Published var undoCountdown: TimeInterval = 0  // For undo timer display

    /// Current recording mode
    private var currentMode: RecordingMode = .normal

    // Timing constants
    private let maxRecordingDuration: TimeInterval = 360  // 6 minutes max
    private let recordingWarningTime: TimeInterval = 300  // Warn at 5 minutes
    private let transcriptionTimeout: TimeInterval = 8    // Show "slow" warning after 8s
    private let transcriptionHardTimeout: TimeInterval = 60  // Give up after 60s
    private let undoDuration: TimeInterval = 5  // 5 seconds to undo

    private let recorder = AudioRecorderService.shared
    private var recordingURL: URL?
    private var recordingTimer: Timer?
    private var transcriptionStartTime: Date?
    private var transcriptionTimeoutTimer: Timer?
    private var transcriptionTask: Task<Void, Never>?
    private var activeTranscriptionID: UUID?
    private var activeTempAudioURL: URL?
    private var activeSavedAudioURL: URL?
    private var activeDurationMs: Int?
    private var activeClientID: UUID?
    private var activePasteTarget: UniversalActionTarget?

    // Undo support
    private var pendingCancelURL: URL?  // Audio file pending deletion
    private var pendingCancelSavedURL: URL?
    private var pendingCancelDurationMs: Int?
    private var pendingCancelClientID: UUID?
    private var pendingCancelPasteTarget: UniversalActionTarget?
    private var undoTimer: Timer?

    private init() {}

    /// Toggle dictation - start if idle, stop if recording (push-to-talk style)
    func toggle() {
        switch state {
        case .idle, .done, .error:
            currentMode = .normal
            startRecording()
        case .recording, .recordingHandsFree, .recordingCommand, .recordingWarning:
            stopAndTranscribe()
        case .transcribing, .transcribingHandsFree, .transcribingCommand, .transcribingSlow:
            // Ignore - wait for transcription
            break
        case .cancelled, .cancelledWhileTranscribing:
            // If clicking again while cancelled, dismiss and start new
            dismissUndo()
            currentMode = .normal
            startRecording()
        }
    }

    /// Toggle hands-free dictation - click to start, click to send
    func toggleHandsFree() {
        switch state {
        case .idle, .done, .error:
            currentMode = .handsFree
            startRecording()
        case .recording, .recordingHandsFree, .recordingCommand, .recordingWarning:
            stopAndTranscribe()
        case .transcribing, .transcribingHandsFree, .transcribingCommand, .transcribingSlow:
            // Ignore - wait for transcription
            break
        case .cancelled, .cancelledWhileTranscribing:
            dismissUndo()
            currentMode = .handsFree
            startRecording()
        }
    }

    /// Start command mode dictation - sends to AI provider after transcription
    func toggleCommandMode() {
        switch state {
        case .idle, .done, .error:
            currentMode = .command
            startRecording()
        case .recording, .recordingHandsFree, .recordingCommand, .recordingWarning:
            stopAndTranscribe()
        case .transcribing, .transcribingHandsFree, .transcribingCommand, .transcribingSlow:
            // Ignore - wait for transcription
            break
        case .cancelled, .cancelledWhileTranscribing:
            dismissUndo()
            currentMode = .command
            startRecording()
        }
    }

    /// Start push-to-talk recording (called when fn key is pressed)
    func startPushToTalk() {
        switch state {
        case .idle, .done, .error:
            currentMode = .normal
            startRecording()
        default:
            break
        }
    }

    /// End push-to-talk recording (called when fn key is released)
    func endPushToTalk() {
        switch state {
        case .recording, .recordingWarning:
            // Only end if we're in normal push-to-talk mode (not hands-free)
            if currentMode == .normal {
                stopAndTranscribe()
            }
        default:
            break
        }
    }

    /// Cancel current recording/transcription - shows undo option
    func cancel() {
        switch state {
        case .recording, .recordingHandsFree, .recordingCommand, .recordingWarning:
            cancelRecordingWithUndo()
        case .transcribing, .transcribingHandsFree, .transcribingCommand, .transcribingSlow:
            cancelTranscriptionWithUndo()
        default:
            break
        }
    }

    /// Called when user clicks Undo within the countdown
    func undoCancel() {
        stopUndoTimer()

        if let url = pendingCancelURL {
            let savedURL = pendingCancelSavedURL
            let durationMs = pendingCancelDurationMs
            let clientID = pendingCancelClientID
            let pasteTarget = pendingCancelPasteTarget
            pendingCancelURL = nil
            pendingCancelSavedURL = nil
            pendingCancelDurationMs = nil
            pendingCancelClientID = nil
            pendingCancelPasteTarget = nil

            // Recording cannot be resumed, but the captured audio can be sent
            // again. Reuse its retained copy so undo does not create an orphan.
            state = .transcribing
            transcriptionStartTime = Date()
            startTranscriptionTimer()
            transcribeAudio(
                url: url,
                durationMs: durationMs,
                existingSavedURL: savedURL,
                clientID: clientID,
                pasteTarget: pasteTarget
            )
        }

        print("[Dictation] Undo - resuming transcription")
    }

    /// Dismiss the undo prompt immediately (user closed it)
    func dismissUndo() {
        stopUndoTimer()
        cleanupPendingCancel()
        state = .idle
    }

    private func cancelRecordingWithUndo() {
        stopRecordingTimer()
        // Stop recording but keep the file for potential undo
        if let url = recorder.stopRecording() {
            pendingCancelURL = url
        }
        pendingCancelSavedURL = nil
        pendingCancelDurationMs = Int(recordingDuration * 1_000)
        pendingCancelClientID = nil
        pendingCancelPasteTarget = nil

        recordingURL = nil
        recordingDuration = 0
        state = .cancelled
        undoCountdown = undoDuration
        startUndoTimer()
        playSubtleSound()
        print("[Dictation] Cancelled with undo option")
    }

    private func cancelTranscriptionWithUndo() {
        stopTranscriptionTimer()
        // Invalidate before cancelling: even if URLSession races and returns a
        // response, the old generation is no longer allowed to save or paste.
        transcriptionTask?.cancel()
        transcriptionTask = nil
        activeTranscriptionID = nil
        pendingCancelURL = activeTempAudioURL ?? recordingURL
        pendingCancelSavedURL = activeSavedAudioURL
        pendingCancelDurationMs = activeDurationMs
        pendingCancelClientID = activeClientID
        pendingCancelPasteTarget = activePasteTarget
        clearActiveTranscriptionResources()
        recordingURL = nil

        state = .cancelledWhileTranscribing
        undoCountdown = undoDuration
        startUndoTimer()
        print("[Dictation] Transcription cancelled with undo option")
    }

    private func startUndoTimer() {
        undoTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.undoCountdown -= 0.1
            if self.undoCountdown <= 0 {
                self.stopUndoTimer()
                self.cleanupPendingCancel()
                self.state = .idle
            }
        }
    }

    private func stopUndoTimer() {
        undoTimer?.invalidate()
        undoTimer = nil
    }

    private func cleanupPendingCancel() {
        if let url = pendingCancelURL {
            try? FileManager.default.removeItem(at: url)
        }
        if let savedURL = pendingCancelSavedURL, savedURL != pendingCancelURL {
            try? FileManager.default.removeItem(at: savedURL)
        }
        pendingCancelURL = nil
        pendingCancelSavedURL = nil
        pendingCancelDurationMs = nil
        pendingCancelClientID = nil
        pendingCancelPasteTarget = nil
    }

    private func startRecording() {
        performStartRecording()
    }

    private func performStartRecording() {
        do {
            recordingURL = try recorder.startRecording()
            recordingDuration = 0

            switch currentMode {
            case .normal:
                state = .recording
            case .handsFree:
                state = .recordingHandsFree
            case .command:
                state = .recordingCommand
            }

            startRecordingTimer()
            playSubtleSound()

            print("[Dictation] Recording started (mode: \(currentMode))")
        } catch let error as AudioRecorderService.RecordingError where error == .permissionNotRequested {
            // First time - need to request permission
            state = .idle
            recorder.requestPermission { [weak self] granted in
                guard let self = self else { return }
                if granted {
                    self.performStartRecording()
                } else {
                    self.state = .error("Microphone permission denied")
                }
            }
        } catch {
            state = .error(error.localizedDescription)
            print("[Dictation] Failed to start: \(error)")
        }
    }

    // MARK: - Recording Timer

    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateRecordingDuration()
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func updateRecordingDuration() {
        recordingDuration += 1

        // Check for warning threshold
        if recordingDuration >= recordingWarningTime && recordingDuration < maxRecordingDuration {
            let remaining = Int(maxRecordingDuration - recordingDuration)
            state = .recordingWarning(message: "\(remaining)s left")
        }

        // Auto-stop at max duration
        if recordingDuration >= maxRecordingDuration {
            print("[Dictation] Max recording duration reached, auto-stopping")
            stopAndTranscribe()
        }
    }

    private func stopAndTranscribe() {
        stopRecordingTimer()

        guard let url = recorder.stopRecording() else {
            state = .error("No recording to process")
            return
        }

        switch currentMode {
        case .normal:
            state = .transcribing
        case .handsFree:
            state = .transcribingHandsFree
        case .command:
            state = .transcribingCommand
        }

        playStopSound()  // Satisfying "sent" sound
        transcriptionStartTime = Date()
        startTranscriptionTimer()
        print("[Dictation] Processing (mode: \(currentMode))...")

        let recordedDurationMs = Int(recordingDuration * 1_000)
        transcribeAudio(url: url, durationMs: recordedDurationMs)
    }

    private func transcribeAudio(
        url: URL,
        durationMs: Int? = nil,
        existingSavedURL: URL? = nil,
        clientID existingClientID: UUID? = nil,
        pasteTarget existingPasteTarget: UniversalActionTarget? = nil
    ) {
        transcriptionTask?.cancel()
        let savedURL = existingSavedURL ?? saveAudioForHistory(tempURL: url)
        let mode = currentMode  // Capture mode before async

        // Get the active dictation mode's transform prompt (if any)
        let dictationMode = AppSettings.shared.activeDictationMode
        let transformPrompt = dictationMode.hasCustomPrompt ? dictationMode.systemPrompt : nil

        let clientID = existingClientID ?? UUID()
        let pasteTarget = existingPasteTarget ?? Self.frontmostApplicationTarget()
        let transcriptionID = UUID()
        activeTranscriptionID = transcriptionID
        activeTempAudioURL = url
        activeSavedAudioURL = savedURL
        activeDurationMs = durationMs
        activeClientID = clientID
        activePasteTarget = pasteTarget

        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await APIService.shared.transcribeDictation(
                    audioURL: url,
                    vocabulary: AppSettings.shared.customVocabulary,
                    transformPrompt: transformPrompt,
                    clientId: clientID.uuidString
                )
                try Task.checkCancellation()

                await MainActor.run {
                    guard self.activeTranscriptionID == transcriptionID,
                          !Task.isCancelled else { return }
                    self.stopTranscriptionTimer()
                    self.lastResult = result
                    var completionWarning = result.warning
                    self.recordingDuration = 0

                    DictationStore.shared.add(
                        result,
                        audioURL: savedURL,
                        durationMs: durationMs,
                        clientId: clientID
                    )

                    // Handle based on mode
                    switch mode {
                    case .normal, .handsFree:
                        if AppSettings.shared.autoPasteAfterDictation {
                            if let pasteTarget,
                               UniversalActionService.targetMatches(
                                   pasteTarget,
                                   Self.frontmostApplicationTarget()
                               ) {
                                if !AccessibilityService.shared.pasteText(
                                    result.polishedText,
                                    expectedTarget: pasteTarget
                                ) {
                                    completionWarning = "Dictation saved. Grant Accessibility access, then use Paste last dictation."
                                }
                            } else {
                                let applicationName = pasteTarget?.applicationName ?? "the original app"
                                completionWarning = "Dictation saved. Focus \(applicationName), then use Paste last dictation."
                            }
                        }
                    case .command:
                        // Voice-driven command mode feeds the local action
                        // palette instead of leaking text into a browser URL.
                        AppDelegate.toggleActionPalette(prefilledText: result.polishedText)
                    }

                    try? FileManager.default.removeItem(at: url)
                    self.recordingURL = nil
                    self.transcriptionTask = nil
                    self.activeTranscriptionID = nil
                    self.clearActiveTranscriptionResources()

                    self.state = completionWarning.map(State.error) ?? .done

                    if completionWarning != nil {
                        self.scheduleErrorDismissal()
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                            Task { @MainActor [weak self] in
                                guard let self else { return }
                                if case .done = self.state {
                                    self.state = .idle
                                }
                            }
                        }
                    }
                }

                print("[Dictation] Transcription completed")
            } catch {
                let wasCancelled = Task.isCancelled || error is CancellationError
                await MainActor.run {
                    guard self.activeTranscriptionID == transcriptionID,
                          !wasCancelled else { return }
                    self.stopTranscriptionTimer()
                    self.state = .error(error.localizedDescription)
                    self.recordingDuration = 0
                    // Provider errors can echo request content. Surface the
                    // localized message in the UI, but keep it out of logs.
                    print("[Dictation] Transcription failed")

                    try? FileManager.default.removeItem(at: url)
                    if let saved = savedURL {
                        DictationStore.shared.addFailed(
                            audioURL: saved,
                            durationMs: durationMs,
                            clientId: clientID
                        )
                    }
                    self.recordingURL = nil
                    self.transcriptionTask = nil
                    self.activeTranscriptionID = nil
                    self.clearActiveTranscriptionResources()

                    self.scheduleErrorDismissal()
                }
            }
        }
    }

    // MARK: - Transcription Timer

    private func startTranscriptionTimer() {
        transcriptionTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkTranscriptionTimeout()
        }
    }

    private func stopTranscriptionTimer() {
        transcriptionTimeoutTimer?.invalidate()
        transcriptionTimeoutTimer = nil
        transcriptionStartTime = nil
    }

    private func checkTranscriptionTimeout() {
        guard let startTime = transcriptionStartTime else { return }
        let elapsed = Date().timeIntervalSince(startTime)

        // Show slow warning
        if elapsed >= transcriptionTimeout && state == .transcribing {
            state = .transcribingSlow
        }

        // Hard timeout - give up
        if elapsed >= transcriptionHardTimeout {
            failActiveTranscriptionDueToTimeout()
        }
    }

    private func failActiveTranscriptionDueToTimeout() {
        guard activeTranscriptionID != nil else {
            stopTranscriptionTimer()
            state = .error("Request timed out. Check your connection and try again.")
            scheduleErrorDismissal()
            return
        }

        let tempURL = activeTempAudioURL
        let savedURL = activeSavedAudioURL
        let durationMs = activeDurationMs
        let clientID = activeClientID

        // Invalidate the generation before cancelling. A provider that ignores
        // transport cancellation still cannot commit a late response.
        activeTranscriptionID = nil
        transcriptionTask?.cancel()
        transcriptionTask = nil
        clearActiveTranscriptionResources()
        stopTranscriptionTimer()
        recordingDuration = 0
        recordingURL = nil

        if let tempURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        if let savedURL {
            DictationStore.shared.addFailed(
                audioURL: savedURL,
                durationMs: durationMs,
                clientId: clientID
            )
        }

        state = .error("Request timed out. The recording was kept so you can retry it.")
        scheduleErrorDismissal()
    }

    private func clearActiveTranscriptionResources() {
        activeTempAudioURL = nil
        activeSavedAudioURL = nil
        activeDurationMs = nil
        activeClientID = nil
        activePasteTarget = nil
    }

    /// Cancels in-flight private work and removes audio that has not yet been
    /// committed to local history. Used by explicit history deletion and a
    /// normal application shutdown so neither path can be undone by a late
    /// provider response.
    func discardActiveWork() {
        stopRecordingTimer()
        stopTranscriptionTimer()
        stopUndoTimer()

        activeTranscriptionID = nil
        transcriptionTask?.cancel()
        transcriptionTask = nil

        var uncommittedAudio = Set<URL>()
        [recordingURL, activeTempAudioURL, activeSavedAudioURL,
         pendingCancelURL, pendingCancelSavedURL].forEach { url in
            if let url { uncommittedAudio.insert(url) }
        }
        if recordingURL != nil, let stoppedURL = recorder.stopRecording() {
            uncommittedAudio.insert(stoppedURL)
        }
        for url in uncommittedAudio {
            try? FileManager.default.removeItem(at: url)
        }

        recordingURL = nil
        clearActiveTranscriptionResources()
        pendingCancelURL = nil
        pendingCancelSavedURL = nil
        pendingCancelDurationMs = nil
        pendingCancelClientID = nil
        pendingCancelPasteTarget = nil
        lastResult = nil
        recordingDuration = 0
        undoCountdown = 0
        state = .idle
    }

    private static func frontmostApplicationTarget() -> UniversalActionTarget? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        return UniversalActionTarget(
            bundleIdentifier: application.bundleIdentifier ?? "",
            processIdentifier: application.processIdentifier,
            applicationName: application.localizedName ?? "the original app"
        )
    }

    private func scheduleErrorDismissal() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .error = self.state {
                    self.state = .idle
                }
            }
        }
    }

    // MARK: - Sound

    private func playSubtleSound() {
        guard AppSettings.shared.dictationSoundEffectsEnabled else { return }
        // Use Tink for a subtle click when starting recording
        if let sound = NSSound(named: "Tink") {
            sound.volume = 0.3
            sound.play()
        }
    }

    private func playStopSound() {
        guard AppSettings.shared.dictationSoundEffectsEnabled else { return }
        // Use Pop for a satisfying "sent" sound when stopping recording
        if let sound = NSSound(named: "Pop") {
            sound.volume = 0.4
            sound.play()
        }
    }

    private func playSuccessSound() {
        guard AppSettings.shared.dictationSoundEffectsEnabled else { return }
        // Use Glass for a satisfying completion sound when text is pasted
        if let sound = NSSound(named: "Glass") {
            sound.volume = 0.3
            sound.play()
        }
    }

    /// Save audio to permanent location for history/retry
    private func saveAudioForHistory(tempURL: URL) -> URL? {
        guard let dir = DictationStore.shared.userDictationsDirectory else { return nil }

        // Create directory if needed
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fileExtension = tempURL.pathExtension.isEmpty ? "m4a" : tempURL.pathExtension.lowercased()
        let filename = "dictation_\(UUID().uuidString).\(fileExtension)"
        let destURL = dir.appendingPathComponent(filename)

        do {
            try FileManager.default.copyItem(at: tempURL, to: destURL)
            return destURL
        } catch {
            print("[Dictation] Failed to save audio for history: \(error)")
            return nil
        }
    }
}
