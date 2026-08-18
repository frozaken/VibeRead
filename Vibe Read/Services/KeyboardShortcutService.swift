import Foundation
import AppKit
import Combine
import Carbon.HIToolbox
import CoreGraphics

/// Service for monitoring global keyboard shortcuts including the fn key
/// Uses NSEvent global monitor which only requires ACCESSIBILITY permission (not Input Monitoring!)
///
/// This is how apps like Wispr Flow do it - they only need Accessibility, not Input Monitoring.
class KeyboardShortcutService: ObservableObject {
    static let shared = KeyboardShortcutService()

    // MARK: - Published State

    @Published var isRecording = false
    @Published var recordedKeys: [KeyCode] = []
    @Published var currentlyPressedKeys: Set<KeyCode> = []
    @Published var fnKeyHeld = false

    // MARK: - Permission State

    /// Whether we have Accessibility permission (this is ALL we need for fn key!)
    @Published var hasAccessibilityPermission = false

    // MARK: - Callbacks

    var onShortcutTriggered: ((ShortcutAction) -> Void)?
    var onPushToTalkStart: (() -> Void)?
    var onPushToTalkEnd: (() -> Void)?

    // MARK: - Private

    private var localMonitor: Any?
    private var globalMonitor: Any?  // Global monitor - only needs Accessibility permission!
    private var cancellables = Set<AnyCancellable>()

    // State tracking
    private var isPushToTalkActive = false
    private var lastFnState = false
    private var fnAloneCandidate = false
    private var activePushToTalkShortcut: CustomKeyboardShortcut?
    private var activeOneShotShortcutID: UUID?

    private init() {
        setupNotifications()
    }

    deinit {
        stopMonitoring()
    }

    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .shortcutsDidChange)
            .sink { [weak self] _ in
                print("[Shortcuts] Configuration changed")
                self?.isPushToTalkActive = false
                self?.activePushToTalkShortcut = nil
                self?.activeOneShotShortcutID = nil
                self?.fnAloneCandidate = false
            }
            .store(in: &cancellables)
    }

    // MARK: - Permission Checking

    /// Check Accessibility permission - this is ALL we need for fn key detection!
    @discardableResult
    func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        hasAccessibilityPermission = trusted
        print("[Shortcuts] Accessibility permission: \(trusted ? "GRANTED" : "NOT GRANTED")")
        return trusted
    }

    // MARK: - Monitoring Control

    func startMonitoring() {
        guard globalMonitor == nil else {
            print("[Shortcuts] Already monitoring")
            return
        }

        print("[Shortcuts] Starting keyboard monitoring...")

        // Check Accessibility permission
        let hasPermission = checkAccessibilityPermission()

        if !hasPermission {
            print("[Shortcuts] ⚠️ No Accessibility permission - global shortcuts won't work")
            print("[Shortcuts] User needs to grant Accessibility in System Settings")
            // Still set up local monitor for when app is focused
            setupLocalMonitor()
            return
        }

        // Set up both local and global monitors
        setupLocalMonitor()
        setupGlobalMonitor()

        print("[Shortcuts] ✓ Keyboard monitoring active - fn key shortcuts will work!")
    }

    /// Set up local monitor - works without any permissions when app is focused
    private func setupLocalMonitor() {
        guard localMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
            self?.handleNSEvent(event, isGlobal: false)
            return event
        }

        print("[Shortcuts] ✓ Local monitor active")
    }

    /// Set up global monitor - requires Accessibility permission (NOT Input Monitoring!)
    private func setupGlobalMonitor() {
        guard globalMonitor == nil else { return }

        // This is the key: NSEvent.addGlobalMonitorForEvents only needs Accessibility permission
        // It can detect flagsChanged which includes the fn key modifier
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
            self?.handleNSEvent(event, isGlobal: true)
        }

        print("[Shortcuts] ✓ Global monitor active (Accessibility permission)")
    }

    /// Retry monitoring after permission is granted
    func retryEventTapSetup() {
        stopMonitoring()
        startMonitoring()
    }

    func stopMonitoring() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        print("[Shortcuts] Stopped monitoring")
    }

    // MARK: - Event Handling (NSEvent-based)

    private func handleNSEvent(_ event: NSEvent, isGlobal: Bool) {
        // Handle recording mode separately
        if isRecording {
            handleRecordingEvent(event)
            return
        }

        // Don't process if hotkeys disabled
        guard AppSettings.shared.dictationHotkeyEnabled else { return }

        switch event.type {
        case .flagsChanged:
            handleFlagsChanged(event: event)
        case .keyDown:
            handleKeyDown(event: event)
        case .keyUp:
            handleKeyUp(event: event)
        default:
            break
        }
    }

    // MARK: - Flags Changed (Modifier Keys including fn)

    private func handleFlagsChanged(event: NSEvent) {
        let flags = event.modifierFlags
        let fnPressed = flags.contains(.function)
        let previousModifiers = currentlyPressedKeys.filter(\.isModifier)

        // Update modifier state
        updateModifiers(from: flags)

        // Handle fn key change
        if fnPressed != lastFnState {
            lastFnState = fnPressed
            fnKeyHeld = fnPressed

            if fnPressed {
                currentlyPressedKeys.insert(.fn)
                // Wait for release before treating fn as an fn-alone action.
                // This leaves time to complete fn+Space or another chord.
                fnAloneCandidate = true
            } else {
                // fn released
                currentlyPressedKeys.remove(.fn)

                // End push-to-talk if active
                if isPushToTalkActive {
                    endPushToTalk()
                } else if fnAloneCandidate,
                          let shortcut = findMatchingShortcut(for: [.fn]),
                          shortcut.action != .pushToTalk {
                    // A lone fn is intentionally dispatched on release so the
                    // user still has time to complete fn+Space or fn+Control.
                    DispatchQueue.main.async {
                        self.onShortcutTriggered?(shortcut.action)
                    }
                }

                fnAloneCandidate = false
            }
        }

        if fnPressed && !flags.intersection([.control, .option, .command, .shift]).isEmpty {
            fnAloneCandidate = false
        }

        resetOneShotDebounceIfNeeded()

        // Modifier-only shortcuts never generate a keyDown event. Trigger
        // when the final modifier is pressed (not when an extra modifier is
        // released), while still deferring a one-shot lone-fn action above.
        let currentModifiers = currentlyPressedKeys.filter(\.isModifier)
        let pressedModifiers = currentModifiers.subtracting(previousModifiers)
        if !pressedModifiers.isEmpty,
           let shortcut = findMatchingShortcut(for: currentlyPressedKeys),
           shortcut.keys.allSatisfy(\.isModifier),
           !(shortcut.keys.count == 1 && shortcut.keys[0] == .fn && shortcut.action != .pushToTalk) {
            activate(shortcut)
        }
        endPushToTalkIfShortcutNoLongerPressed()
    }

    // MARK: - Key Down

    private func handleKeyDown(event: NSEvent) {
        let keyCode = event.keyCode
        let isRepeat = event.isARepeat

        guard let key = KeyCode.from(keyCode: keyCode) else { return }

        // Skip repeats for shortcut detection
        if isRepeat { return }

        currentlyPressedKeys.insert(key)
        if key != .fn { fnAloneCandidate = false }
        resetOneShotDebounceIfNeeded()

        // Check for matching shortcut
        if let shortcut = findMatchingShortcut(for: currentlyPressedKeys) {
            activate(shortcut)
        }
    }

    // MARK: - Key Up

    private func handleKeyUp(event: NSEvent) {
        if let key = KeyCode.from(keyCode: event.keyCode) {
            currentlyPressedKeys.remove(key)
        }
        resetOneShotDebounceIfNeeded()
        endPushToTalkIfShortcutNoLongerPressed()
    }

    private func endPushToTalkIfShortcutNoLongerPressed() {
        guard isPushToTalkActive, let shortcut = activePushToTalkShortcut else { return }
        if !Set(shortcut.keys).isSubset(of: currentlyPressedKeys) {
            endPushToTalk()
        }
    }

    private func endPushToTalk() {
        guard isPushToTalkActive else { return }
        isPushToTalkActive = false
        activePushToTalkShortcut = nil
        print("[Shortcuts] Push-to-talk ended")
        DispatchQueue.main.async {
            self.onPushToTalkEnd?()
        }
    }

    private func activate(_ shortcut: CustomKeyboardShortcut) {
        if shortcut.action == .pushToTalk {
            guard !isPushToTalkActive else { return }
            isPushToTalkActive = true
            activePushToTalkShortcut = shortcut
            fnAloneCandidate = false
            print("[Shortcuts] Push-to-talk started")
            DispatchQueue.main.async {
                self.onPushToTalkStart?()
            }
            return
        }

        guard activeOneShotShortcutID != shortcut.id else { return }
        activeOneShotShortcutID = shortcut.id
        print("[Shortcuts] \(shortcut.action.displayName) triggered")
        DispatchQueue.main.async {
            self.onShortcutTriggered?(shortcut.action)
        }
    }

    private func resetOneShotDebounceIfNeeded() {
        guard let activeOneShotShortcutID else { return }
        guard let shortcut = AppSettings.shared.shortcuts.first(where: { $0.id == activeOneShotShortcutID }),
              Set(shortcut.keys) == currentlyPressedKeys else {
            self.activeOneShotShortcutID = nil
            return
        }
    }

    // MARK: - Shortcut Matching

    private func findMatchingShortcut(for keys: Set<KeyCode>) -> CustomKeyboardShortcut? {
        let shortcuts = AppSettings.shared.shortcuts
        return shortcuts.first { Set($0.keys) == keys }
    }

    // MARK: - Modifier Updates

    private func updateModifiers(from flags: NSEvent.ModifierFlags) {
        if flags.contains(.control) {
            currentlyPressedKeys.insert(.control)
        } else {
            currentlyPressedKeys.remove(.control)
        }

        if flags.contains(.option) {
            currentlyPressedKeys.insert(.option)
        } else {
            currentlyPressedKeys.remove(.option)
        }

        if flags.contains(.command) {
            currentlyPressedKeys.insert(.command)
        } else {
            currentlyPressedKeys.remove(.command)
        }

        if flags.contains(.shift) {
            currentlyPressedKeys.insert(.shift)
        } else {
            currentlyPressedKeys.remove(.shift)
        }
    }

    // MARK: - Recording Mode Event Handling

    private func handleRecordingEvent(_ event: NSEvent) {
        if event.type == .flagsChanged {
            let flags = event.modifierFlags
            currentlyPressedKeys.removeAll()

            if flags.contains(.function) { currentlyPressedKeys.insert(.fn) }
            if flags.contains(.control) { currentlyPressedKeys.insert(.control) }
            if flags.contains(.option) { currentlyPressedKeys.insert(.option) }
            if flags.contains(.command) { currentlyPressedKeys.insert(.command) }
            if flags.contains(.shift) { currentlyPressedKeys.insert(.shift) }

            recordedKeys = Array(currentlyPressedKeys)
        } else if event.type == .keyDown {
            if let key = KeyCode.from(keyCode: event.keyCode) {
                currentlyPressedKeys.insert(key)
                recordedKeys = Array(currentlyPressedKeys)
            }
        }
    }

    // MARK: - Recording Mode

    func startRecording() {
        isRecording = true
        recordedKeys = []
        currentlyPressedKeys = []
        print("[Shortcuts] Started recording")
    }

    func stopRecording() -> [KeyCode] {
        isRecording = false
        let keys = recordedKeys
        recordedKeys = []
        print("[Shortcuts] Stopped recording: \(keys.map { $0.displayName })")
        return keys
    }

    func cancelRecording() {
        isRecording = false
        recordedKeys = []
        print("[Shortcuts] Cancelled recording")
    }
}

private extension KeyCode {
    var isModifier: Bool {
        switch self {
        case .fn, .control, .option, .command, .shift:
            return true
        default:
            return false
        }
    }
}
