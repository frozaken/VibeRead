import Foundation
import AppKit
import ApplicationServices
import Combine
import CoreGraphics

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

    /// Simulate a key press with modifiers
    private func simulateKeyPress(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)

        // Key down
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = modifiers
            keyDown.post(tap: .cghidEventTap)
        }

        // Key up
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            keyUp.flags = modifiers
            keyUp.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Paste Text

    /// Paste text at the current cursor position. The caller should surface a
    /// permission error when this returns false. When possible, the existing
    /// clipboard is restored after the target app has consumed Cmd+V.
    @discardableResult
    func pasteText(
        _ text: String,
        expectedTarget: UniversalActionTarget? = nil
    ) -> Bool {
        guard checkPermission() else {
            print("[Accessibility] Cannot paste without Accessibility permission")
            return false
        }

        // Revalidate at the actual event-posting boundary. Callers may have
        // checked focus before entering this method, but provider completions
        // must never rely on an earlier snapshot if the foreground app changed.
        if let expectedTarget {
            guard let application = NSWorkspace.shared.frontmostApplication,
                  application.processIdentifier == expectedTarget.processIdentifier,
                  expectedTarget.bundleIdentifier.isEmpty
                    || application.bundleIdentifier == expectedTarget.bundleIdentifier else {
                print("[Accessibility] Paste target changed")
                return false
            }
        }

        let pasteboard = NSPasteboard.general
        let previousItems = (pasteboard.pasteboardItems ?? []).map {
            PasteboardItemSnapshot(item: $0)
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let temporaryChangeCount = pasteboard.changeCount

        // Snapshotting a rich or lazily provided clipboard can take time. Check
        // focus again after that work and immediately before posting Cmd+V. If
        // the target changed, restore the clipboard synchronously and refuse
        // the paste rather than sending private output to another app.
        if let expectedTarget {
            guard let application = NSWorkspace.shared.frontmostApplication,
                  application.processIdentifier == expectedTarget.processIdentifier,
                  expectedTarget.bundleIdentifier.isEmpty
                    || application.bundleIdentifier == expectedTarget.bundleIdentifier else {
                if pasteboard.changeCount == temporaryChangeCount {
                    pasteboard.clearContents()
                    let restoredItems = previousItems.map(\.pasteboardItem)
                    if !restoredItems.isEmpty {
                        pasteboard.writeObjects(restoredItems)
                    }
                }
                print("[Accessibility] Paste target changed")
                return false
            }
        }

        // NSPasteboard writes are synchronous. Post Cmd+V immediately so a
        // target check performed by the caller cannot go stale during an
        // arbitrary delay before the key event is sent.
        simulateKeyPress(keyCode: 9, modifiers: .maskCommand)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            // Never overwrite a clipboard change the user made while the
            // synthetic paste was in flight.
            guard pasteboard.changeCount == temporaryChangeCount else { return }
            pasteboard.clearContents()
            let restoredItems = previousItems.map(\.pasteboardItem)
            if !restoredItems.isEmpty {
                pasteboard.writeObjects(restoredItems)
            }
        }

        // Do not log pasted content. It may be a private dictation or selection.
        print("[Accessibility] Pasted text")
        return true
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
