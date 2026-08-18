import Foundation
import AppKit
import ApplicationServices
import Combine
import CoreGraphics

/// Service for system-wide accessibility features including:
/// - Permission management (Accessibility only - this is ALL we need for fn key!)
/// - Capturing selected text from any application
///
/// NOTE: We only need Accessibility permission for fn key detection.
/// NSEvent.addGlobalMonitorForEvents with .flagsChanged works with just Accessibility.
/// We do NOT need Input Monitoring (that's only needed for CGEventTap).
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
        hasAccessibilityPermission = trusted
        print("[Accessibility] Permission: \(trusted ? "GRANTED" : "NOT GRANTED")")

        if trusted {
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
        let trusted = AXIsProcessTrustedWithOptions(options)
        hasAccessibilityPermission = trusted
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
            return getSelectedTextViaClipboard()
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
            return getSelectedTextViaClipboard()
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

        print("[Accessibility] No selected text found via AX, trying clipboard method")
        return getSelectedTextViaClipboard()
    }

    /// Fallback method: simulate Cmd+C to copy selection to clipboard
    /// This works when direct AX access fails (e.g., some apps don't expose selection)
    private func getSelectedTextViaClipboard() -> String? {
        // Save current clipboard
        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> (String, Data)? in
            guard let type = item.types.first,
                  let data = item.data(forType: type) else { return nil }
            return (type.rawValue, data)
        }

        // Clear clipboard
        pasteboard.clearContents()

        // Simulate Cmd+C
        simulateKeyPress(keyCode: 8, modifiers: .maskCommand) // 'C' key

        // Wait a bit for the copy to complete
        Thread.sleep(forTimeInterval: 0.1)

        // Get clipboard content
        let copiedText = pasteboard.string(forType: .string)

        // Restore original clipboard
        pasteboard.clearContents()
        if let savedItems = savedItems {
            for (typeStr, data) in savedItems {
                if let type = NSPasteboard.PasteboardType(rawValue: typeStr) as NSPasteboard.PasteboardType? {
                    pasteboard.setData(data, forType: type)
                }
            }
        }

        if let text = copiedText, !text.isEmpty {
            print("[Accessibility] Got text via clipboard fallback")
            return text
        }

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

    /// Paste text at current cursor position
    /// Copies to clipboard then simulates Cmd+V
    func pasteText(_ text: String) {
        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure clipboard is ready
        Thread.sleep(forTimeInterval: 0.05)

        // Simulate Cmd+V (V key = 9)
        simulateKeyPress(keyCode: 9, modifiers: .maskCommand)

        // Do not log pasted content. It may be a private dictation or selection.
        print("[Accessibility] Pasted text")
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

// MARK: - Key Codes Reference
// Common key codes for macOS:
// C = 8, V = 9, R = 15, Space = 49
// Command = .maskCommand, Shift = .maskShift, Option = .maskAlternate
