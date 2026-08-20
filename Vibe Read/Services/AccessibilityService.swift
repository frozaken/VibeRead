import Foundation
import AppKit
import ApplicationServices
import Combine
import CoreGraphics

enum PasteFailure: Equatable {
    case accessibilityDenied
    case targetChanged
    case eventUnavailable
    case clipboardUnavailable
}

enum PasteOutcome: Equatable {
    case pasted
    case copiedOnly(PasteFailure)
    case failed(PasteFailure)

    var didPaste: Bool {
        if case .pasted = self { return true }
        return false
    }

    var isOnClipboard: Bool {
        switch self {
        case .pasted, .copiedOnly:
            return true
        case .failed:
            return false
        }
    }
}

/// Permission and focused-application operations that macOS protects behind
/// Accessibility. Reserved ordinary shortcuts do not depend on this service.
class AccessibilityService: ObservableObject {
    static let shared = AccessibilityService()

    @Published var hasAccessibilityPermission = false
    @Published var isPollingForPermission = false

    private var permissionPollingTimer: Timer?
    private var pollingStartTime: Date?

    private init() {
        _ = checkPermission()
    }

    // MARK: - Accessibility Permission

    /// Check if app has accessibility permissions
    @discardableResult
    func checkPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        let permissionWasGranted = hasAccessibilityPermission
        hasAccessibilityPermission = trusted
        print("[Accessibility] Permission: \(trusted ? "GRANTED" : "NOT GRANTED")")

        if trusted && !permissionWasGranted {
            stopPermissionPolling()
            // Notify keyboard service to start monitoring
            KeyboardShortcutService.shared.retryEventTapSetup()
        }

        return trusted
    }

    /// Request accessibility permission - this DOES show a system dialog
    func requestAccessibilityPermission() {
        print("[Accessibility] Requesting permission (will show dialog)...")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        let trusted = checkPermission()
        print("[Accessibility] Dialog shown, current status: \(trusted ? "granted" : "pending")")

        // Start polling in case user grants it in System Settings
        if !trusted {
            startPollingForAccessibility()
        }
    }

    /// Open System Settings to Accessibility pane
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Permission Polling

    /// Start polling for Accessibility permission
    private func startPollingForAccessibility() {
        stopPermissionPolling()
        isPollingForPermission = true
        pollingStartTime = Date()

        print("[Accessibility] Started polling for permission...")

        permissionPollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollForAccessibilityPermission()
        }
    }

    private func pollForAccessibilityPermission() {
        if let startTime = pollingStartTime, Date().timeIntervalSince(startTime) > 120 {
            print("[Accessibility] Stopped polling (timeout)")
            stopPermissionPolling()
            return
        }

        let granted = checkPermission()
        if granted {
            print("[Accessibility] Permission detected!")
            stopPermissionPolling()
        }
    }

    func stopPermissionPolling() {
        permissionPollingTimer?.invalidate()
        permissionPollingTimer = nil
        isPollingForPermission = false
        pollingStartTime = nil
    }

    /// Manually refresh permission status
    func refreshAllPermissions() {
        _ = checkPermission()
    }

    // MARK: - Get Selected Text

    /// Get the currently selected text from the frontmost application
    /// Returns nil if no text is selected or accessibility permission is denied
    func getSelectedText() -> String? {
        guard checkPermission() else {
            print("[Accessibility] Cannot get selection - no permission")
            return nil
        }

        // Get the system-wide accessibility element
        let systemWideElement = AXUIElementCreateSystemWide()

        // Get the focused application
        var focusedApp: AnyObject?
        let appResult = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )

        guard appResult == .success, let appElement = focusedApp else {
            print("[Accessibility] Could not get focused application")
            return nil
        }

        // Get the focused UI element within the application
        var focusedElement: AnyObject?
        let elementResult = AXUIElementCopyAttributeValue(
            appElement as! AXUIElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard elementResult == .success, let element = focusedElement else {
            print("[Accessibility] Could not get focused element")
            return nil
        }

        // Try to get selected text directly
        var selectedText: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )

        if textResult == .success, let text = selectedText as? String, !text.isEmpty {
            // Selected text can contain passwords, private messages, or other
            // sensitive content. Never include it in console output.
            print("[Accessibility] Got selected text via AX")
            return text
        }

        // Fallback: try selected text range
        var selectedTextRange: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedTextRange
        )

        if rangeResult == .success {
            // Get text for the range
            var textForRange: AnyObject?
            let paramResult = AXUIElementCopyParameterizedAttributeValue(
                element as! AXUIElement,
                kAXStringForRangeParameterizedAttribute as CFString,
                selectedTextRange!,
                &textForRange
            )

            if paramResult == .success, let text = textForRange as? String, !text.isEmpty {
                print("[Accessibility] Got selected text via range")
                return text
            }
        }

        // Do not synthesize Cmd+C here. That approach can mutate or partially
        // restore rich clipboard contents. Callers can offer the existing
        // clipboard as an explicit, visibly labelled source instead.
        print("[Accessibility] No selected text found via AX")
        return nil
    }

    /// Simulate a key press with modifiers. Returning false means the event
    /// could not be constructed, so callers can keep a clipboard fallback.
    private func simulateKeyPress(keyCode: CGKeyCode, modifiers: CGEventFlags) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: true
        ), let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: false
        ) else { return false }

        keyDown.flags = modifiers
        keyUp.flags = modifiers
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    // MARK: - Paste Text

    /// Put completed text on the clipboard without posting a key event.
    /// This is the fail-safe when no trustworthy paste destination exists.
    @discardableResult
    func copyTextToClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    /// Paste text at the current cursor position and leave the text on the
    /// clipboard. Keeping the output there is the recovery path when an app
    /// such as an Electron editor does not consume the synthetic Cmd+V.
    func pasteTextWithOutcome(
        _ text: String,
        expectedTarget: UniversalActionTarget? = nil
    ) -> PasteOutcome {
        let outcome = Self.deliverText(
            text,
            expectedTarget: expectedTarget,
            pasteboard: .general,
            hasAccessibilityPermission: checkPermission(),
            currentTarget: {
                guard let application = NSWorkspace.shared.frontmostApplication else {
                    return nil
                }
                return UniversalActionTarget(
                    bundleIdentifier: application.bundleIdentifier ?? "",
                    processIdentifier: application.processIdentifier,
                    applicationName: application.localizedName ?? "the original app"
                )
            },
            postPasteShortcut: { [weak self] in
                self?.simulateKeyPress(keyCode: 9, modifiers: .maskCommand) ?? false
            }
        )

        switch outcome {
        case .pasted:
            print("[Accessibility] Paste shortcut posted; text retained on clipboard")
        case .copiedOnly(.accessibilityDenied):
            print("[Accessibility] Copied text; cannot paste without Accessibility permission")
        case .copiedOnly(.targetChanged):
            print("[Accessibility] Copied text; paste target changed")
        case .copiedOnly(.eventUnavailable):
            print("[Accessibility] Copied text; paste shortcut unavailable")
        case .copiedOnly(.clipboardUnavailable), .failed:
            print("[Accessibility] Could not place text on the clipboard")
        }

        return outcome
    }

    /// Paste text for an explicit action such as Cmd+E Apply. Unlike completed
    /// dictation delivery, this keeps the user's existing clipboard intact.
    @discardableResult
    func pasteText(
        _ text: String,
        expectedTarget: UniversalActionTarget? = nil
    ) -> Bool {
        Self.deliverTextTemporarily(
            text,
            expectedTarget: expectedTarget,
            pasteboard: .general,
            hasAccessibilityPermission: checkPermission(),
            currentTarget: Self.frontmostApplicationTarget,
            postPasteShortcut: { [weak self] in
                self?.simulateKeyPress(keyCode: 9, modifiers: .maskCommand) ?? false
            },
            scheduleRestore: { restore in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    restore()
                }
            }
        )
    }

    /// Deterministic core used by unit tests and the live Accessibility path.
    /// The clipboard write deliberately precedes every guarded paste outcome,
    /// so a completed dictation is recoverable without opening History.
    static func deliverText(
        _ text: String,
        expectedTarget: UniversalActionTarget?,
        pasteboard: NSPasteboard,
        hasAccessibilityPermission: Bool,
        currentTarget: () -> UniversalActionTarget?,
        postPasteShortcut: () -> Bool
    ) -> PasteOutcome {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            return .failed(.clipboardUnavailable)
        }

        guard hasAccessibilityPermission else {
            return .copiedOnly(.accessibilityDenied)
        }

        if let expectedTarget,
           !targetMatches(expectedTarget, currentTarget()) {
            return .copiedOnly(.targetChanged)
        }

        guard postPasteShortcut() else {
            return .copiedOnly(.eventUnavailable)
        }
        return .pasted
    }

    /// Deterministic core for explicit actions whose output should not replace
    /// the user's clipboard after Cmd+V has been posted.
    static func deliverTextTemporarily(
        _ text: String,
        expectedTarget: UniversalActionTarget?,
        pasteboard: NSPasteboard,
        hasAccessibilityPermission: Bool,
        currentTarget: () -> UniversalActionTarget?,
        postPasteShortcut: () -> Bool,
        scheduleRestore: (@escaping () -> Void) -> Void
    ) -> Bool {
        guard hasAccessibilityPermission else { return false }
        if let expectedTarget,
           !targetMatches(expectedTarget, currentTarget()) {
            return false
        }

        let previousItems = (pasteboard.pasteboardItems ?? []).map {
            PasteboardItemSnapshot(item: $0)
        }
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            restore(previousItems, to: pasteboard)
            return false
        }
        let temporaryChangeCount = pasteboard.changeCount

        // Snapshotting a lazy pasteboard can take time, so validate again at
        // the actual event-posting boundary.
        if let expectedTarget,
           !targetMatches(expectedTarget, currentTarget()) {
            if pasteboard.changeCount == temporaryChangeCount {
                restore(previousItems, to: pasteboard)
            }
            return false
        }

        guard postPasteShortcut() else {
            if pasteboard.changeCount == temporaryChangeCount {
                restore(previousItems, to: pasteboard)
            }
            return false
        }

        scheduleRestore {
            guard pasteboard.changeCount == temporaryChangeCount else { return }
            restore(previousItems, to: pasteboard)
        }
        return true
    }

    private static func targetMatches(
        _ expected: UniversalActionTarget,
        _ current: UniversalActionTarget?
    ) -> Bool {
        guard let current else { return false }
        return expected.processIdentifier == current.processIdentifier
            && (expected.bundleIdentifier.isEmpty
                || expected.bundleIdentifier == current.bundleIdentifier)
    }

    private static func frontmostApplicationTarget() -> UniversalActionTarget? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return UniversalActionTarget(
            bundleIdentifier: application.bundleIdentifier ?? "",
            processIdentifier: application.processIdentifier,
            applicationName: application.localizedName ?? "the original app"
        )
    }

    private static func restore(
        _ snapshots: [PasteboardItemSnapshot],
        to pasteboard: NSPasteboard
    ) {
        pasteboard.clearContents()
        let items = snapshots.map(\.pasteboardItem)
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    // MARK: - Get Frontmost App Info

    /// Get info about the frontmost application (for debugging)
    func getFrontmostAppInfo() -> (name: String, bundleId: String)? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return (
            name: frontApp.localizedName ?? "Unknown",
            bundleId: frontApp.bundleIdentifier ?? "Unknown"
        )
    }
}

private struct PasteboardItemSnapshot {
    let values: [(type: NSPasteboard.PasteboardType, data: Data)]

    init(item: NSPasteboardItem) {
        values = item.types.compactMap { type in
            item.data(forType: type).map { (type, $0) }
        }
    }

    var pasteboardItem: NSPasteboardItem {
        let item = NSPasteboardItem()
        for value in values {
            item.setData(value.data, forType: value.type)
        }
        return item
    }
}

// MARK: - Key Codes Reference
// Common key codes for macOS:
// C = 8, V = 9, R = 15, Space = 49
// Command = .maskCommand, Shift = .maskShift, Option = .maskAlternate
