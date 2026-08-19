import Foundation
import AppKit
import Combine
import Carbon.HIToolbox
import CoreGraphics

/// Routes configurable shortcuts through the narrowest macOS API that can
/// represent them. Ordinary key chords use Carbon so they are globally
/// reserved and consumed. fn and modifier-only shortcuts use NSEvent because
/// they need press and release state that Carbon cannot express.
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

    /// Ordinary chords are reserved through Carbon and therefore work even
    /// before Accessibility is granted. Any entries here could not be reserved
    /// exclusively, usually because another app already owns the chord.
    @Published private(set) var shortcutRegistrationFailures: [String: String] = [:]

    // MARK: - Callbacks

    var onShortcutTriggered: ((ShortcutAction) -> Void)?
    var onPushToTalkStart: (() -> Void)?
    var onPushToTalkEnd: (() -> Void)?

    // MARK: - Private

    private var localMonitor: Any?
    private var globalMonitor: Any?  // Global monitor - only needs Accessibility permission!
    private var cancellables = Set<AnyCancellable>()

    // Carbon is the only system API in this app that reserves an ordinary
    // global chord instead of passively observing it. fn-based and
    // modifier-only shortcuts still use NSEvent because their press/release
    // semantics cannot be represented by RegisterEventHotKey.
    private static let hotKeySignature: OSType = 0x56425244 // "VBRD"
    private var carbonEventHandler: EventHandlerRef?
    private var carbonHotKeyReferences: [UInt32: EventHotKeyRef] = [:]
    private var carbonShortcuts: [UInt32: CustomKeyboardShortcut] = [:]
    private var carbonShortcutIDs = Set<UUID>()
    private var activeCarbonPushToTalkID: UInt32?
    private var activeCarbonOneShotID: UInt32?

    // State tracking
    private var isPushToTalkActive = false
    private var lastFnState = false
    private var fnAloneCandidate = false
    private var fnHandsFreeStopTriggeredOnPress = false
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
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                print("[Shortcuts] Configuration changed")
                guard let self else { return }
                if self.isPushToTalkActive {
                    self.endPushToTalk()
                }
                self.activeCarbonPushToTalkID = nil
                self.activeCarbonOneShotID = nil
                self.activeOneShotShortcutID = nil
                self.fnAloneCandidate = false
                self.fnHandsFreeStopTriggeredOnPress = false
                self.registerCarbonHotKeys()
            }
            .store(in: &cancellables)
    }

    // MARK: - Permission Checking

    /// Accessibility is needed for fn/modifier observation, selection, and paste.
    @discardableResult
    func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        hasAccessibilityPermission = trusted
        print("[Shortcuts] Accessibility permission: \(trusted ? "GRANTED" : "NOT GRANTED")")
        return trusted
    }

    // MARK: - Monitoring Control

    func startMonitoring() {
        guard localMonitor == nil, carbonEventHandler == nil else {
            print("[Shortcuts] Already monitoring")
            return
        }

        print("[Shortcuts] Starting keyboard monitoring...")

        // Reserve ordinary chords first. Carbon hotkeys do not require
        // Accessibility and, unlike NSEvent monitors, keep Cmd+E from also
        // reaching the foreground application.
        installCarbonEventHandlerIfNeeded()
        registerCarbonHotKeys()
        setupLocalMonitor()

        // Check Accessibility permission
        let hasPermission = checkAccessibilityPermission()

        if !hasPermission {
            print("[Shortcuts] Accessibility is needed for fn shortcuts, selection, and pasting")
            return
        }

        // fn and modifier-only shortcuts still need press/release observation.
        setupGlobalMonitor()

        print("[Shortcuts] Keyboard monitoring active")
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

    /// Set up global monitor for fn and modifier-only shortcuts.
    private func setupGlobalMonitor() {
        guard globalMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
            self?.handleNSEvent(event, isGlobal: true)
        }

        print("[Shortcuts] ✓ Global monitor active (Accessibility permission)")
    }

    /// Retry monitoring after permission is granted
    func retryEventTapSetup() {
        if carbonEventHandler == nil {
            installCarbonEventHandlerIfNeeded()
            registerCarbonHotKeys()
        }
        let hasPermission = checkAccessibilityPermission()
        setupLocalMonitor()
        if hasPermission {
            setupGlobalMonitor()
        }
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
        unregisterCarbonHotKeys()
        if let carbonEventHandler {
            RemoveEventHandler(carbonEventHandler)
            self.carbonEventHandler = nil
        }
        print("[Shortcuts] Stopped monitoring")
    }

    // MARK: - Reserved Carbon Hotkeys

    private static let carbonHotKeyHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        var actualSize = 0
        let parameterStatus = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            &actualSize,
            &hotKeyID
        )
        guard parameterStatus == noErr,
              hotKeyID.signature == KeyboardShortcutService.hotKeySignature else {
            return OSStatus(eventNotHandledErr)
        }

        let service = Unmanaged<KeyboardShortcutService>
            .fromOpaque(userData)
            .takeUnretainedValue()
        let identifier = hotKeyID.id
        let eventKind = GetEventKind(event)
        DispatchQueue.main.async {
            service.handleCarbonHotKey(id: identifier, eventKind: eventKind)
        }
        return noErr
    }

    private func installCarbonEventHandlerIfNeeded() {
        guard carbonEventHandler == nil else { return }

        let eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]
        var handler: EventHandlerRef?
        let status = eventTypes.withUnsafeBufferPointer { buffer in
            InstallEventHandler(
                GetApplicationEventTarget(),
                Self.carbonHotKeyHandler,
                buffer.count,
                buffer.baseAddress,
                Unmanaged.passUnretained(self).toOpaque(),
                &handler
            )
        }
        guard status == noErr else {
            print("[Shortcuts] Could not install reserved-hotkey handler (OSStatus \(status))")
            return
        }
        carbonEventHandler = handler
    }

    private func registerCarbonHotKeys() {
        unregisterCarbonHotKeys()
        shortcutRegistrationFailures = [:]
        installCarbonEventHandlerIfNeeded()
        guard carbonEventHandler != nil else { return }

        var nextIdentifier: UInt32 = 1
        for shortcut in AppSettings.shared.shortcuts {
            guard let representation = carbonRepresentation(for: shortcut) else { continue }
            // Carbon-eligible shortcuts must never fall back to passive
            // NSEvent observation. If reservation fails, firing the action
            // while also leaking the chord to the foreground app is worse
            // than leaving the shortcut unavailable and reporting the error.
            carbonShortcutIDs.insert(shortcut.id)

            let hotKeyID = EventHotKeyID(
                signature: Self.hotKeySignature,
                id: nextIdentifier
            )
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                representation.keyCode,
                representation.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                OptionBits(kEventHotKeyExclusive),
                &reference
            )

            if status == noErr, let reference {
                carbonHotKeyReferences[nextIdentifier] = reference
                carbonShortcuts[nextIdentifier] = shortcut
                nextIdentifier += 1
            } else {
                shortcutRegistrationFailures[shortcut.action.rawValue] =
                    "Could not reserve \(shortcut.displayString) (OSStatus \(status))"
                print("[Shortcuts] Could not reserve \(shortcut.action.displayName)")
            }
        }
    }

    private func unregisterCarbonHotKeys() {
        for reference in carbonHotKeyReferences.values {
            UnregisterEventHotKey(reference)
        }
        carbonHotKeyReferences.removeAll()
        carbonShortcuts.removeAll()
        carbonShortcutIDs.removeAll()
        activeCarbonPushToTalkID = nil
        activeCarbonOneShotID = nil
    }

    static func carbonRepresentation(
        for keys: [KeyCode]
    ) -> (keyCode: UInt32, modifiers: UInt32)? {
        guard !keys.contains(.fn) else { return nil }

        let ordinaryKeys = keys.filter { !$0.isModifier }
        guard ordinaryKeys.count == 1,
              let ordinaryKey = ordinaryKeys.first,
              let ordinaryKeyCode = ordinaryKey.cgKeyCode else {
            return nil
        }

        // Never reserve a bare letter, number, Return, or Space system-wide.
        // Function keys are intentionally useful as single-key bindings.
        let hasChordModifier = keys.contains {
            [.command, .shift, .option, .control].contains($0)
        }
        guard hasChordModifier || ordinaryKey.isFunctionKey else { return nil }

        var modifiers: UInt32 = 0
        for key in keys {
            switch key {
            case .command: modifiers |= UInt32(cmdKey)
            case .shift: modifiers |= UInt32(shiftKey)
            case .option: modifiers |= UInt32(optionKey)
            case .control: modifiers |= UInt32(controlKey)
            default: break
            }
        }
        return (UInt32(ordinaryKeyCode), modifiers)
    }

    private func carbonRepresentation(
        for shortcut: CustomKeyboardShortcut
    ) -> (keyCode: UInt32, modifiers: UInt32)? {
        Self.carbonRepresentation(for: shortcut.keys)
    }

    private func handleCarbonHotKey(id: UInt32, eventKind: UInt32) {
        guard let shortcut = carbonShortcuts[id] else { return }

        switch eventKind {
        case UInt32(kEventHotKeyPressed):
            guard AppSettings.shared.dictationHotkeyEnabled,
                  !isRecording else { return }
            guard activeCarbonOneShotID != id,
                  activeCarbonPushToTalkID != id else { return }
            if shortcut.action == .pushToTalk {
                guard !isPushToTalkActive else { return }
                activeCarbonPushToTalkID = id
                isPushToTalkActive = true
                activePushToTalkShortcut = shortcut
                onPushToTalkStart?()
            } else {
                activeCarbonOneShotID = id
                onShortcutTriggered?(shortcut.action)
            }

        case UInt32(kEventHotKeyReleased):
            if activeCarbonPushToTalkID == id {
                activeCarbonPushToTalkID = nil
                endPushToTalk()
            }
            if activeCarbonOneShotID == id {
                activeCarbonOneShotID = nil
            }

        default:
            break
        }
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
                let fnShortcut = findMatchingShortcut(for: [.fn])
                if Self.shouldFinishHandsFree(
                    isHandsFreeRecording: DictationService.shared.isHandsFreeRecording,
                    shortcutAction: fnShortcut?.action
                ), let shortcut = fnShortcut {
                    // A second fn press finishes hands-free recording on
                    // key-down. Some macOS configurations do not reliably
                    // deliver the matching global key-up while recording.
                    fnAloneCandidate = false
                    fnHandsFreeStopTriggeredOnPress = true
                    DispatchQueue.main.async {
                        self.onShortcutTriggered?(shortcut.action)
                    }
                } else {
                    // Wait for release before treating the first fn press as
                    // an fn-alone action. This leaves time for fn+Space.
                    fnAloneCandidate = true
                    fnHandsFreeStopTriggeredOnPress = false
                }
            } else {
                // fn released
                currentlyPressedKeys.remove(.fn)

                // End push-to-talk if active
                if isPushToTalkActive {
                    endPushToTalk()
                } else if fnHandsFreeStopTriggeredOnPress {
                    // Key-down already sent the stop action. Do not send it
                    // again if recording state has not updated before key-up.
                } else if Self.shouldFinishHandsFreeOnRelease(
                    isHandsFreeRecording: DictationService.shared.isHandsFreeRecording,
                    shortcutAction: findMatchingShortcut(for: [.fn])?.action,
                    didTriggerOnPress: fnHandsFreeStopTriggeredOnPress
                ), let shortcut = findMatchingShortcut(for: [.fn]) {
                    // Also finish on the second release. This catches the
                    // macOS path where a modifier-down transition is
                    // coalesced while the nonactivating HUD is visible.
                    DispatchQueue.main.async {
                        self.onShortcutTriggered?(shortcut.action)
                    }
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
                fnHandsFreeStopTriggeredOnPress = false
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

    static func shouldFinishHandsFree(
        isHandsFreeRecording: Bool,
        shortcutAction: ShortcutAction?
    ) -> Bool {
        isHandsFreeRecording && shortcutAction == .handsFree
    }

    static func shouldFinishHandsFreeOnRelease(
        isHandsFreeRecording: Bool,
        shortcutAction: ShortcutAction?,
        didTriggerOnPress: Bool
    ) -> Bool {
        !didTriggerOnPress && shouldFinishHandsFree(
            isHandsFreeRecording: isHandsFreeRecording,
            shortcutAction: shortcutAction
        )
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
            // Bare typing keys are not valid global actions. Function keys
            // are Carbon-managed above; NSEvent is reserved for real chords.
            guard shortcut.keys.contains(where: \.isModifier) else { return }
            // Every ordinary chord belongs exclusively to Carbon. Ignore its
            // NSEvent copy even when registration failed, otherwise the action
            // and the foreground app would both receive the shortcut.
            if carbonRepresentation(for: shortcut) != nil { return }
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
        // Existing reserved chords would otherwise be consumed before the
        // focused shortcut editor can record them.
        unregisterCarbonHotKeys()
        isRecording = true
        recordedKeys = []
        currentlyPressedKeys = []
        print("[Shortcuts] Started recording")
    }

    func stopRecording() -> [KeyCode] {
        isRecording = false
        let keys = recordedKeys
        recordedKeys = []
        registerCarbonHotKeys()
        print("[Shortcuts] Stopped recording: \(keys.map { $0.displayName })")
        return keys
    }

    func cancelRecording() {
        isRecording = false
        recordedKeys = []
        registerCarbonHotKeys()
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

    var isFunctionKey: Bool {
        switch self {
        case .f1, .f2, .f3, .f4, .f5, .f6,
             .f7, .f8, .f9, .f10, .f11, .f12:
            return true
        default:
            return false
        }
    }
}
