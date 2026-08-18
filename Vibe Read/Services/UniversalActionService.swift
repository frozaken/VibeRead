import Foundation
import AppKit
import Combine

/// Executes the deliberately small, local-first Cmd+E action set.
@MainActor
final class UniversalActionService: ObservableObject {
    static let shared = UniversalActionService()

    @Published var isProcessing = false
    @Published var lastError: Error?
    @Published var lastOutput: String?

    private init() {}

    func readSelection(_ text: String, source: String? = nil) async {
        _ = source
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        lastError = nil
        InstantTTSService.shared.speak(text)
    }

    func readClipboard() async {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            NSSound.beep()
            return
        }
        await readSelection(text)
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func pasteLastDictation() {
        guard let text = DictationStore.shared.items.first?.polishedText, !text.isEmpty else {
            NSSound.beep()
            return
        }
        AccessibilityService.shared.pasteText(text)
    }

    /// Runs a user-defined prompt through their configured provider and
    /// replaces the selected text with the result.
    func run(_ action: LocalTextAction, on text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            return
        }

        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        do {
            let output = try await APIService.shared.transformText(text, systemPrompt: action.prompt)
            lastOutput = output
            AccessibilityService.shared.pasteText(output)
        } catch {
            lastError = error
            NSSound.beep()
        }
    }

    func openVibeRead() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { !($0 is NSPanel) })?.makeKeyAndOrderFront(nil)
    }
}
