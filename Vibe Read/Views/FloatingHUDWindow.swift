import SwiftUI
import AppKit
import Combine

/// Minimal pill indicator - top center of screen
/// Shows only when generating/playing, disappears when idle
/// Expands to show audio controls when playing or dictation controls when recording
@MainActor
class FloatingHUDController: NSObject, ObservableObject {
    static let shared = FloatingHUDController()

    private var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?
    private var cancellables = Set<AnyCancellable>()
    private var hideTimer: Timer?

    enum HUDState: Equatable {
        case hidden
        case generating(message: String)  // Now includes descriptive message
        case playing
        case error
        // Dictation states
        case recording
        case recordingHandsFree  // Hands-free mode recording (green indicator)
        case recordingCommand  // Command mode recording (yellow indicator)
        case recordingWarning(message: String)  // Time limit warning
        case transcribing
        case transcribingHandsFree  // Hands-free mode transcribing
        case transcribingCommand  // Command mode transcribing
        case transcribingSlow  // Taking longer than expected
        case dictationDone
        case cancelled  // With undo option
        case cancelledWhileTranscribing  // Cancelled during processing

        // Helper for backward compatibility
        static var generating: HUDState { .generating(message: "Generating...") }
    }

    @Published var state: HUDState = .hidden
    @Published var warningMessage: String = ""
    @Published var generatingMessage: String = "Generating..."
    @Published var undoProgress: CGFloat = 1.0  // 1.0 = full, 0.0 = expired

    // Track both TTS and dictation active states for side-by-side
    @Published var isTTSActive = false
    @Published var isDictationActive = false
    @Published var isHovering = false

    // Prevent race conditions during state transitions
    private var isHideAnimating = false

    // Pill size constants
    private let compactWidth: CGFloat = 48
    private let compactHeight: CGFloat = 28
    private let expandedWidth: CGFloat = 140
    private let expandedHeight: CGFloat = 32
    // Dictation recording pill size (compact like Wispr Flow)
    // Height includes space above for floating warnings/tooltips
    private let dictationWidth: CGFloat = 140
    private let dictationPillHeight: CGFloat = 32
    private let dictationWindowHeight: CGFloat = 90  // Extra space for overlays above
    // Transcribing sphere - perfect circle
    private let transcribingSphereSize: CGFloat = 32
    // Cancelled/undo pill (minimal)
    private let cancelledWidth: CGFloat = 220
    private let cancelledHeight: CGFloat = 40
    // Warning pill (wider for message)
    private let warningWidth: CGFloat = 280
    private let warningHeight: CGFloat = 56
    // Combined TTS + Dictation pill
    private let combinedWidth: CGFloat = 290
    private let combinedHeight: CGFloat = 90  // Same height as dictation for overlays
    // TTS player pill (minimal)
    private let ttsPlayerWidth: CGFloat = 140
    private let ttsPlayerHeight: CGFloat = 32
    // Bottom padding above dock
    private let bottomPadding: CGFloat = 8

    private var escapeMonitor: Any?
    private var speedBoostMonitor: Any?

    override init() {
        super.init()
        createWindow()
        observeTTSState()
        setupKeyMonitors()
    }

    private func setupKeyMonitors() {
        // Escape key monitor for dictation cancel (global to work even when app not focused)
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return }  // 53 = Escape key

            // Only handle if dictation is recording or transcribing
            let dictationState = DictationService.shared.state
            switch dictationState {
            case .recording, .recordingHandsFree, .recordingCommand, .recordingWarning, .transcribing, .transcribingHandsFree, .transcribingCommand, .transcribingSlow:
                DictationService.shared.cancel()
            default:
                break
            }
        }

        // Also add local monitor for when app is focused
        _ = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event }  // 53 = Escape key

            let dictationState = DictationService.shared.state
            switch dictationState {
            case .recording, .recordingHandsFree, .recordingCommand, .recordingWarning, .transcribing, .transcribingHandsFree, .transcribingCommand, .transcribingSlow:
                DictationService.shared.cancel()
                return nil  // Consume the event
            default:
                return event
            }
        }

        // 'G' key monitor for speed boost (when hovering over HUD)
        speedBoostMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            // Check if 'g' key (keyCode 5) and TTS is playing and user is hovering
            guard event.keyCode == 5,
                  self.isHovering,
                  InstantTTSService.shared.isSpeaking else {
                return event
            }

            InstantTTSService.shared.toggleSpeedBoost()
            return nil  // Consume the event
        }
    }

    deinit {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = speedBoostMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }

    private func createWindow() {
        let pillView = PillIndicatorView()
            .environmentObject(self)

        hostingView = NSHostingView(rootView: AnyView(pillView))
        hostingView?.frame = NSRect(x: 0, y: 0, width: compactWidth, height: compactHeight)

        window = NSWindow(
            contentRect: hostingView!.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window?.contentView = hostingView
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.level = .floating
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window?.isReleasedWhenClosed = false
        window?.hasShadow = true
        window?.ignoresMouseEvents = true // Click-through by default

        positionWindow()
    }

    private func updateWindowSize(expanded: Bool) {
        guard let window = window, let hostingView = hostingView else { return }

        let newWidth = expanded ? expandedWidth : compactWidth
        let newHeight = expanded ? expandedHeight : compactHeight

        // Calculate new origin to keep centered at bottom
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame  // Excludes dock and menu bar
        let newX = visibleFrame.midX - (newWidth / 2)
        let newY = visibleFrame.minY + bottomPadding  // Just above dock

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(
                NSRect(x: newX, y: newY, width: newWidth, height: newHeight),
                display: true
            )
        }

        hostingView.frame.size = CGSize(width: newWidth, height: newHeight)
    }

    private func positionWindow() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame  // Excludes dock and menu bar
        let width = state == .playing ? expandedWidth : compactWidth
        let x = visibleFrame.midX - (width / 2)
        let y = visibleFrame.minY + bottomPadding  // Just above dock
        window?.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func observeTTSState() {
        InstantTTSService.shared.$isLoading
            .combineLatest(
                InstantTTSService.shared.$isSpeaking,
                InstantTTSService.shared.$error
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading, isSpeaking, error in
                guard let self = self else { return }

                // Update isTTSActive FIRST, before state update
                let wasActive = self.isTTSActive
                self.isTTSActive = isLoading || isSpeaking

                print("[HUD] TTS state changed - loading: \(isLoading), speaking: \(isSpeaking), wasActive: \(wasActive), isActive: \(self.isTTSActive)")

                // Only proceed with state update if there's a meaningful change
                self.updateState(isLoading: isLoading, isSpeaking: isSpeaking, error: error)
            }
            .store(in: &cancellables)

        // Observe DictationService state
        DictationService.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dictationState in
                // Track if dictation is active (recording or transcribing)
                switch dictationState {
                case .recording, .recordingHandsFree, .recordingCommand, .recordingWarning, .transcribing, .transcribingHandsFree, .transcribingCommand, .transcribingSlow:
                    self?.isDictationActive = true
                default:
                    self?.isDictationActive = false
                }
                self?.handleDictationState(dictationState)
            }
            .store(in: &cancellables)

        // Observe undo countdown for progress bar
        DictationService.shared.$undoCountdown
            .receive(on: DispatchQueue.main)
            .sink { [weak self] countdown in
                // Convert countdown (0-5s) to progress (0-1)
                self?.undoProgress = CGFloat(countdown / 5.0)
            }
            .store(in: &cancellables)
    }

    private func handleDictationState(_ dictationState: DictationService.State) {
        switch dictationState {
        case .idle:
            // Only hide if we were showing dictation states
            if case .recording = state { hide() }
            else if case .recordingHandsFree = state { hide() }
            else if case .recordingCommand = state { hide() }
            else if case .recordingWarning = state { hide() }
            else if case .transcribing = state { hide() }
            else if case .transcribingHandsFree = state { hide() }
            else if case .transcribingCommand = state { hide() }
            else if case .transcribingSlow = state { hide() }
            else if case .dictationDone = state { hide() }
            else if case .cancelled = state { hide() }
            else if case .cancelledWhileTranscribing = state { hide() }
            warningMessage = ""

        case .recording:
            state = .recording
            setInteractive(true)
            updateWindowSizeForDictation()
            show()

        case .recordingHandsFree:
            state = .recordingHandsFree
            setInteractive(true)
            updateWindowSizeForDictation()
            show()

        case .recordingCommand:
            state = .recordingCommand
            setInteractive(true)
            updateWindowSizeForDictation()
            show()

        case .recordingWarning(let message):
            warningMessage = message
            state = .recordingWarning(message: message)
            setInteractive(true)
            updateWindowSizeForWarning()
            show()

        case .transcribing:
            state = .transcribing
            setInteractive(true)
            updateWindowSizeForTranscribingSphere()
            show()

        case .transcribingHandsFree:
            state = .transcribingHandsFree
            setInteractive(true)
            updateWindowSizeForTranscribingSphere()
            show()

        case .transcribingCommand:
            state = .transcribingCommand
            setInteractive(true)
            updateWindowSizeForTranscribingSphere()
            show()

        case .transcribingSlow:
            state = .transcribingSlow
            setInteractive(true)
            updateWindowSizeForSlowWarning()
            show()

        case .done:
            state = .dictationDone
            setInteractive(false)
            updateWindowSize(expanded: false)
            show()
            scheduleHide(after: 0.3)

        case .cancelled:
            state = .cancelled
            setInteractive(true)
            updateWindowSizeForCancelled()
            show()

        case .cancelledWhileTranscribing:
            state = .cancelledWhileTranscribing
            setInteractive(true)
            updateWindowSizeForCancelled()
            show()

        case .error(let message):
            warningMessage = message
            state = .error
            setInteractive(true)
            updateWindowSizeForWarning()
            show()
            scheduleHide(after: 4)
        }
    }

    private func updateWindowSizeForCancelled() {
        guard let window = window, let hostingView = hostingView else { return }

        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let newX = visibleFrame.midX - (cancelledWidth / 2)
        let newY = visibleFrame.minY + bottomPadding

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(
                NSRect(x: newX, y: newY, width: cancelledWidth, height: cancelledHeight),
                display: true
            )
        }

        hostingView.frame.size = CGSize(width: cancelledWidth, height: cancelledHeight)
    }

    private func updateWindowSizeForWarning() {
        guard let window = window, let hostingView = hostingView else { return }

        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let newX = visibleFrame.midX - (warningWidth / 2)
        let newY = visibleFrame.minY + bottomPadding

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(
                NSRect(x: newX, y: newY, width: warningWidth, height: warningHeight),
                display: true
            )
        }

        hostingView.frame.size = CGSize(width: warningWidth, height: warningHeight)
    }

    private func updateWindowSizeForDictation() {
        guard let window = window, let hostingView = hostingView else { return }

        // If TTS is also active, use combined width
        let useWidth = isTTSActive ? combinedWidth : dictationWidth

        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let newX = visibleFrame.midX - (useWidth / 2)
        let newY = visibleFrame.minY + bottomPadding

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(
                NSRect(x: newX, y: newY, width: useWidth, height: dictationWindowHeight),
                display: true
            )
        }

        hostingView.frame.size = CGSize(width: useWidth, height: dictationWindowHeight)
    }

    private func updateWindowSizeForTTSPlayer() {
        guard let window = window, let hostingView = hostingView else { return }

        // If dictation is also active, use combined dimensions
        let useWidth = isDictationActive ? combinedWidth : ttsPlayerWidth
        let useHeight = isDictationActive ? combinedHeight : ttsPlayerHeight

        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let newX = visibleFrame.midX - (useWidth / 2)
        let newY = visibleFrame.minY + bottomPadding

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(
                NSRect(x: newX, y: newY, width: useWidth, height: useHeight),
                display: true
            )
        }

        hostingView.frame.size = CGSize(width: useWidth, height: useHeight)
    }

    private func updateWindowSizeForTranscribingSphere() {
        guard let window = window, let hostingView = hostingView else { return }

        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let newX = visibleFrame.midX - (transcribingSphereSize / 2)
        let newY = visibleFrame.minY + bottomPadding

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(
                NSRect(x: newX, y: newY, width: transcribingSphereSize, height: transcribingSphereSize),
                display: true
            )
        }

        hostingView.frame.size = CGSize(width: transcribingSphereSize, height: transcribingSphereSize)
    }

    private func updateWindowSizeForSlowWarning() {
        guard let window = window, let hostingView = hostingView else { return }

        let slowWidth: CGFloat = 280
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let newX = visibleFrame.midX - (slowWidth / 2)
        let newY = visibleFrame.minY + bottomPadding

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(
                NSRect(x: newX, y: newY, width: slowWidth, height: warningHeight),
                display: true
            )
        }

        hostingView.frame.size = CGSize(width: slowWidth, height: warningHeight)
    }

    private func updateState(isLoading: Bool, isSpeaking: Bool, error: Error?) {
        cancelHideTimer()

        print("[HUD] updateState - isLoading: \(isLoading), isSpeaking: \(isSpeaking), error: \(error != nil), dictationActive: \(isDictationActive)")

        if error != nil {
            state = .error
            setInteractive(false)
            updateWindowSize(expanded: false)
            show()
            scheduleHide(after: 2)
        } else if isLoading {
            // Don't override dictation states while loading TTS
            if !isDictationActive {
                showGenerating(message: generatingMessage.isEmpty ? "Generating audio..." : generatingMessage)
            }
        } else if isSpeaking {
            print("[HUD] Transitioning to PLAYING state")
            // Don't override dictation states - we'll show combined view
            if !isDictationActive {
                state = .playing
            }
            setInteractive(true) // Enable clicks for player controls
            updateWindowSizeForTTSPlayer()
            show()
            // DON'T auto-hide when playing - user needs controls
            print("[HUD] Playing state - window visible: \(window?.isVisible ?? false), alpha: \(window?.alphaValue ?? 0)")
        } else {
            // Only hide if dictation is not active
            if !isDictationActive {
                setInteractive(false)
                updateWindowSize(expanded: false)
                hide()
            }
        }
    }

    private func setInteractive(_ interactive: Bool) {
        window?.ignoresMouseEvents = !interactive
    }

    func show() {
        // Cancel any pending hide animation
        isHideAnimating = false

        // Force window visible immediately (handles race conditions)
        window?.alphaValue = 1
        window?.orderFrontRegardless()
    }

    func hide() {
        // Don't hide if we're in a TTS active state - the player should stay visible
        if isTTSActive {
            print("[HUD] Blocking hide - TTS is active")
            return
        }

        guard window?.isVisible == true, window?.alphaValue ?? 0 > 0 else { return }

        isHideAnimating = true

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }

                // If TTS became active during animation, restore visibility
                if self.isTTSActive {
                    self.isHideAnimating = false
                    self.window?.alphaValue = 1
                    self.window?.orderFrontRegardless()
                    return
                }

                self.isHideAnimating = false
                self.window?.orderOut(nil)
                self.state = .hidden
            }
        })
    }

    // MARK: - Generating State Helpers

    /// Show generating state with a descriptive message
    func showGenerating(message: String) {
        generatingMessage = message
        state = .generating(message: message)
        setInteractive(true)  // Allow cancel
        updateWindowSizeForGenerating()
        show()
    }

    /// Update the generating message without changing state
    func updateGeneratingMessage(_ message: String) {
        generatingMessage = message
        if case .generating = state {
            state = .generating(message: message)
        }
    }

    /// Cancel current generation
    func cancelGenerating() {
        // Notify the TTS service to cancel
        InstantTTSService.shared.stop()
        hide()
    }

    private func updateWindowSizeForGenerating() {
        guard let window = window, let hostingView = hostingView else { return }

        let genWidth: CGFloat = 200
        let genHeight: CGFloat = 40

        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let newX = visibleFrame.midX - (genWidth / 2)
        let newY = visibleFrame.minY + bottomPadding

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(
                NSRect(x: newX, y: newY, width: genWidth, height: genHeight),
                display: true
            )
        }

        hostingView.frame.size = CGSize(width: genWidth, height: genHeight)
    }

    private func scheduleHide(after seconds: TimeInterval) {
        hideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Don't hide while generating or playing
                if case .generating = self.state { return }
                if self.state == .playing { return }
                self.hide()
            }
        }
    }

    private func cancelHideTimer() {
        hideTimer?.invalidate()
        hideTimer = nil
    }
}

// MARK: - Pill View

struct PillIndicatorView: View {
    @EnvironmentObject var controller: FloatingHUDController
    @ObservedObject private var ttsService = InstantTTSService.shared
    @State private var isHovering = false

    var body: some View {
        Group {
            // Check if both TTS and dictation are active - show combined view
            if controller.isTTSActive && controller.isDictationActive {
                combinedPill
            } else {
                // Show single state pill
                switch controller.state {
                case .generating:
                    generatingPill
                case .playing:
                    minimalAudioPlayerPill
                case .recording:
                    dictationRecordingPill(mode: .normal)
                case .recordingHandsFree:
                    dictationRecordingPill(mode: .handsFree)
                case .recordingCommand:
                    dictationRecordingPill(mode: .command)
                case .recordingWarning:
                    dictationWarningPill
                case .transcribing, .transcribingHandsFree, .transcribingCommand:
                    transcribingSpherePill
                case .transcribingSlow:
                    slowTranscribingPill
                case .error:
                    errorPill
                case .cancelled:
                    cancelledPill
                case .cancelledWhileTranscribing:
                    cancelledWhileTranscribingPill
                default:
                    compactPill
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: controller.state)
        .onHover { hovering in
            isHovering = hovering
            controller.setHovering(hovering)
        }
    }

    // MARK: - Generating Pill (with message and cancel)

    private var generatingPill: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 16, height: 16)

            Text(controller.generatingMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            HoverButton(
                action: { controller.cancelGenerating() },
                icon: "xmark",
                size: 20,
                iconSize: 9
            )
        }
        .padding(.horizontal, 12)
        .frame(width: 200, height: 40)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    // Recording mode for display purposes
    enum RecordingDisplayMode {
        case normal
        case handsFree
        case command
    }

    // MARK: - Combined TTS + Dictation Pill (side by side)

    private var combinedPill: some View {
        let displayMode: RecordingDisplayMode = {
            switch controller.state {
            case .recordingCommand: return .command
            case .recordingHandsFree: return .handsFree
            default: return .normal
            }
        }()

        return VStack {
            Spacer()  // Push pill to bottom

            HStack(spacing: 8) {
                // TTS player section
                minimalAudioPlayerContent

                // Divider
                Rectangle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 1, height: 20)

                // Dictation section
                dictationRecordingContent(mode: displayMode)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            )
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Compact Pill (generating, error, dictation states)

    private var compactPill: some View {
        HStack(spacing: 4) {
            compactIndicator
        }
        .frame(width: 48, height: 28)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        )
        .overlay(
            Capsule()
                .stroke(compactBorderColor, lineWidth: 0.5)
        )
    }

    // MARK: - Minimal Audio Player Pill (clean, no moving parts)

    private var minimalAudioPlayerPill: some View {
        HStack(spacing: 8) {
            minimalAudioPlayerContent
        }
        .padding(.horizontal, 10)
        .frame(width: 140, height: 32)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        )
        .overlay(
            Capsule()
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 0.5)
        )
    }

    // Content view that can be used in combined pill
    private var minimalAudioPlayerContent: some View {
        HStack(spacing: 8) {
            // Play/Pause button
            Button(action: {
                ttsService.toggle()
            }) {
                Image(systemName: ttsService.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HoverScaleButtonStyle())

            // Static speaker icon (no animation)
            Image(systemName: ttsService.isPaused ? "speaker.fill" : "speaker.wave.2.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.accentColor)

            // Speed indicator - subtle, changes with boost
            Text(speedIndicatorText)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(ttsService.isSpeedBoosted ? .accentColor : .secondary)
                .frame(minWidth: 24)
                .help(isHovering ? "Press 'g' to toggle speed" : "")

            // Stop/close button
            HoverButton(
                action: { ttsService.stop() },
                icon: "xmark",
                size: 18,
                iconSize: 8
            )
        }
    }

    private var speedIndicatorText: String {
        let rate = ttsService.isSpeedBoosted ? AppSettings.shared.speedBoostMultiplier : 1.0
        if rate == 1.0 {
            return "1x"
        } else {
            return String(format: "%.1fx", rate)
        }
    }

    // MARK: - Dictation Recording Pill (minimal, almost invisible)

    private func dictationRecordingPill(mode: RecordingDisplayMode) -> some View {
        DictationPillWithWarning(mode: mode)
    }

    // Content view that can be used in combined pill
    private func dictationRecordingContent(mode: RecordingDisplayMode) -> some View {
        DictationRecordingContentView(mode: mode)
    }

    // MARK: - Transcribing Sphere (perfect circle with spinner)

    private var transcribingSpherePill: some View {
        ProgressView()
            .scaleEffect(0.7)
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            )
            .overlay(
                Circle()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
    }

    // MARK: - Recording Warning Pill (time limit approaching)

    private var dictationWarningPill: some View {
        VStack(spacing: 4) {
            // Top row: waveform + stop
            HStack(spacing: 8) {
                HoverButton(
                    action: { DictationService.shared.cancel() },
                    icon: "xmark",
                    size: 20,
                    iconSize: 9
                )

                AudioWaveformView()

                Button(action: {
                    DictationService.shared.toggle()
                }) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.8))
                        .frame(width: 10, height: 10)
                        .padding(6)
                        .background(Circle().fill(Color.primary.opacity(0.1)))
                }
                .buttonStyle(HoverScaleButtonStyle())
            }

            // Warning message
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 9))
                Text(controller.warningMessage)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 240, height: 56)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Slow Transcribing Pill

    private var slowTranscribingPill: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)

                Text("Taking longer than usual...")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                HoverButton(
                    action: { DictationService.shared.cancel() },
                    icon: "xmark",
                    size: 18,
                    iconSize: 8
                )
            }

            Text("Your dictation is saved. You can retry in the app.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 280, height: 56)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    // MARK: - Error Pill

    private var isPermissionError: Bool {
        let msg = controller.warningMessage.lowercased()
        return msg.contains("permission") || msg.contains("microphone") || msg.contains("accessibility")
    }

    private var errorPill: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: isPermissionError ? "lock.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(isPermissionError ? .orange : .secondary)

                Text(isPermissionError ? "Permission needed" : "Something went wrong")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                HoverButton(
                    action: {
                        FloatingHUDController.shared.hide()
                    },
                    icon: "xmark",
                    size: 18,
                    iconSize: 8
                )
            }

            HStack(spacing: 8) {
                Text(controller.warningMessage)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if isPermissionError {
                    Spacer()
                    Button(action: openRelevantSettings) {
                        Text("Open Settings")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: isPermissionError ? 280 : 240, height: 56)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isPermissionError ? Color.orange.opacity(0.3) : Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    private func openRelevantSettings() {
        let msg = controller.warningMessage.lowercased()
        if msg.contains("microphone") {
            // Open microphone settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        } else if msg.contains("accessibility") {
            // Open accessibility settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        } else {
            // Generic privacy settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                NSWorkspace.shared.open(url)
            }
        }
        FloatingHUDController.shared.hide()
    }

    // MARK: - Cancelled Pill (with undo countdown)

    private var cancelledPill: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Cancelled")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                Button(action: {
                    DictationService.shared.undoCancel()
                }) {
                    Text("Undo")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)

                HoverButton(
                    action: { DictationService.shared.dismissUndo() },
                    icon: "xmark",
                    size: 18,
                    iconSize: 8
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // Progress bar - white line that shrinks over 5 seconds
            GeometryReader { geo in
                let progressWidth = max(0, min(geo.size.width, geo.size.width * controller.undoProgress))
                Rectangle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: progressWidth.isFinite ? progressWidth : 0, height: 2)
                    .animation(.linear(duration: 0.1), value: controller.undoProgress)
            }
            .frame(height: 2)
            .padding(.horizontal, 2)
            .padding(.bottom, 2)
        }
        .frame(width: 220, height: 40)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Cancelled While Transcribing Pill

    private var cancelledWhileTranscribingPill: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Cancelled")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                Button(action: {
                    DictationService.shared.undoCancel()
                }) {
                    Text("Undo")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)

                HoverButton(
                    action: { DictationService.shared.dismissUndo() },
                    icon: "xmark",
                    size: 18,
                    iconSize: 8
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            // Progress bar - white line that shrinks over 5 seconds
            GeometryReader { geo in
                let progressWidth = max(0, min(geo.size.width, geo.size.width * controller.undoProgress))
                Rectangle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: progressWidth.isFinite ? progressWidth : 0, height: 2)
                    .animation(.linear(duration: 0.1), value: controller.undoProgress)
            }
            .frame(height: 2)
            .padding(.horizontal, 2)
            .padding(.bottom, 2)
        }
        .frame(width: 220, height: 40)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var compactIndicator: some View {
        switch controller.state {
        case .hidden, .playing, .recording, .recordingHandsFree, .recordingCommand, .recordingWarning, .error, .transcribing, .transcribingHandsFree, .transcribingCommand, .transcribingSlow, .cancelled, .cancelledWhileTranscribing, .generating:
            // These have their own expanded pills
            EmptyView()

        case .dictationDone:
            // Very subtle - just a small dot that quickly fades
            Circle()
                .fill(Color.primary.opacity(0.4))
                .frame(width: 6, height: 6)
        }
    }

    private var compactBorderColor: Color {
        // Keep all borders subtle and uniform
        return .primary.opacity(0.08)
    }
}

// MARK: - Audio-Reactive Waveform

struct AudioWaveformView: View {
    @ObservedObject private var recorder = AudioRecorderService.shared

    // Number of bars in waveform
    private let barCount = 9

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(index: index, audioLevel: recorder.audioLevel)
            }
        }
        .frame(width: 50, height: 16)
    }
}

struct WaveformBar: View {
    let index: Int
    let audioLevel: Float

    // Each bar has a slightly different response for visual variety
    private var barMultiplier: CGFloat {
        let multipliers: [CGFloat] = [0.6, 0.8, 1.0, 0.9, 1.0, 0.9, 1.0, 0.8, 0.6]
        return multipliers[index % multipliers.count]
    }

    private var barHeight: CGFloat {
        let minHeight: CGFloat = 4
        let maxHeight: CGFloat = 14
        let level = CGFloat(audioLevel) * barMultiplier
        return minHeight + (maxHeight - minHeight) * level
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.primary.opacity(0.5))
            .frame(width: 2.5, height: barHeight)
            .animation(.easeOut(duration: 0.08), value: audioLevel)
    }
}

// MARK: - Hover Button Component

struct HoverButton: View {
    let action: () -> Void
    let icon: String
    var size: CGFloat = 20
    var iconSize: CGFloat = 9

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(isHovered ? .primary : .secondary)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(isHovered ? 0.15 : 0.08))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Hover Scale Button Style

struct HoverScaleButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : (isHovered ? 1.05 : 1.0))
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - Dictation Pill With Warning (handles silence detection at pill level)

private struct DictationPillWithWarning: View {
    let mode: PillIndicatorView.RecordingDisplayMode

    @State private var showSilenceWarning = false
    @State private var silenceTimer: Timer?
    @State private var lastAudioDetectedTime = Date()

    @ObservedObject private var recorder = AudioRecorderService.shared

    var body: some View {
        VStack(spacing: 8) {
            // Silence warning at top (visible in the space above pill)
            if showSilenceWarning {
                SilenceWarningView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer()

            // The actual pill at bottom
            HStack(spacing: 8) {
                DictationRecordingContentView(mode: mode)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            )
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
        .onAppear {
            startSilenceDetection()
        }
        .onDisappear {
            stopSilenceDetection()
        }
        .onChange(of: recorder.audioLevel) { newLevel in
            if newLevel > 0.05 {
                lastAudioDetectedTime = Date()
                if showSilenceWarning {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showSilenceWarning = false
                    }
                }
            }
        }
    }

    private func startSilenceDetection() {
        lastAudioDetectedTime = Date()
        showSilenceWarning = false

        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let silenceDuration = Date().timeIntervalSince(lastAudioDetectedTime)
            if silenceDuration >= 4.0 && !showSilenceWarning {
                withAnimation(.easeOut(duration: 0.2)) {
                    showSilenceWarning = true
                }
            }
        }
    }

    private func stopSilenceDetection() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }
}

// MARK: - Dictation Recording Content (buttons and waveform)

private struct DictationRecordingContentView: View {
    let mode: PillIndicatorView.RecordingDisplayMode

    @State private var cancelHovered = false
    @State private var completeHovered = false

    private var completeLabel: String {
        switch mode {
        case .command: return "Send"
        case .handsFree: return "Done"
        case .normal: return "Done"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Cancel button with hover label
            LabeledHoverButton(
                action: { DictationService.shared.cancel() },
                icon: "xmark",
                label: "Cancel",
                size: 20,
                iconSize: 9,
                isHovered: $cancelHovered
            )

            // Audio-reactive waveform
            AudioWaveformView()

            // Stop/complete button with hover label
            CompleteButton(
                mode: mode,
                label: completeLabel,
                isHovered: $completeHovered
            )
        }
    }
}

// MARK: - Silence Warning View

private struct SilenceWarningView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.orange)

                Text("No audio detected")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
            }

            Text("Check if your mic is muted or working.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Labeled Hover Button (with floating label above)

private struct LabeledHoverButton: View {
    let action: () -> Void
    let icon: String
    let label: String
    var size: CGFloat = 20
    var iconSize: CGFloat = 9
    @Binding var isHovered: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(isHovered ? .primary : .secondary)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(isHovered ? 0.15 : 0.08))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            // Floating label above the button
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                )
                .opacity(isHovered ? 1 : 0)
                .offset(y: isHovered ? -24 : -16)
                .animation(.easeOut(duration: 0.15), value: isHovered)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Complete Button (stop square with floating label above)

private struct CompleteButton: View {
    let mode: PillIndicatorView.RecordingDisplayMode
    let label: String
    @Binding var isHovered: Bool

    var body: some View {
        Button(action: {
            switch mode {
            case .command:
                DictationService.shared.toggleCommandMode()
            case .handsFree:
                DictationService.shared.toggleHandsFree()
            case .normal:
                DictationService.shared.toggle()
            }
        }) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.primary.opacity(isHovered ? 1.0 : 0.8))
                .frame(width: 10, height: 10)
                .padding(6)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(isHovered ? 0.15 : 0.1))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .overlay(alignment: .top) {
            // Floating label above the button
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                )
                .opacity(isHovered ? 1 : 0)
                .offset(y: isHovered ? -24 : -16)
                .animation(.easeOut(duration: 0.15), value: isHovered)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
