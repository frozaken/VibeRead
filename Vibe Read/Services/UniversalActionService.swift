import Foundation
import AppKit
import Combine

enum UniversalActionError: Error, LocalizedError, Equatable {
    case emptyInput
    case noOutput
    case accessibilityRequired
    case originalApplicationUnavailable
    case targetApplicationChanged(String)
    case pasteFailed

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Select text or choose the labelled clipboard source first."
        case .noOutput:
            return "There is no generated text to apply."
        case .accessibilityRequired:
            return "Grant Accessibility access before applying text."
        case .originalApplicationUnavailable:
            return "The original application is no longer available. Copy the result instead."
        case .targetApplicationChanged(let name):
            return "Focus \(name) again before applying, or copy the result."
        case .pasteFailed:
            return "Vibe Read could not apply the text. Copy the result instead."
        }
    }
}

struct UniversalActionTarget: Equatable, Sendable {
    let bundleIdentifier: String
    let processIdentifier: pid_t
    let applicationName: String
}

/// Executes the deliberately small, local-first Cmd+E action set. Provider
/// output is always previewed. It is never pasted until the user explicitly
/// chooses Apply, and Apply is limited to the application that opened Cmd+E.
@MainActor
final class UniversalActionService: ObservableObject {
    typealias TransformOperation = @Sendable (String, String) async throws -> String
    typealias CurrentApplication = () -> UniversalActionTarget?
    typealias AccessibilityReadiness = () -> Bool
    typealias PasteOperation = (String, UniversalActionTarget?) -> Bool
    typealias ExtractOperation = @Sendable (URL) async throws -> ExtractedContent

    static let shared = UniversalActionService()

    @Published private(set) var isProcessing = false
    @Published private(set) var lastError: Error?
    @Published private(set) var lastOutput: String?
    @Published private(set) var didCopyOutput = false
    @Published private(set) var lastNotice: String?

    private let transform: TransformOperation
    private let currentApplication: CurrentApplication
    private let isAccessibilityReady: AccessibilityReadiness
    private let paste: PasteOperation
    private let extract: ExtractOperation
    private var actionTask: Task<Void, Never>?
    private var generationID: UUID?
    private var targetApplication: UniversalActionTarget?

    init(
        transform: @escaping TransformOperation = { text, prompt in
            try await APIService.shared.transformText(text, systemPrompt: prompt)
        },
        currentApplication: @escaping CurrentApplication = {
            guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
            return UniversalActionTarget(
                bundleIdentifier: application.bundleIdentifier ?? "",
                processIdentifier: application.processIdentifier,
                applicationName: application.localizedName ?? "the original app"
            )
        },
        isAccessibilityReady: @escaping AccessibilityReadiness = {
            AccessibilityService.shared.checkPermission()
        },
        paste: @escaping PasteOperation = { text, target in
            AccessibilityService.shared.pasteText(text, expectedTarget: target)
        },
        extract: @escaping ExtractOperation = { url in
            try await ContentExtractionService().extract(url)
        }
    ) {
        self.transform = transform
        self.currentApplication = currentApplication
        self.isAccessibilityReady = isAccessibilityReady
        self.paste = paste
        self.extract = extract
    }

    func beginSession(
        targetBundleIdentifier: String,
        processIdentifier: pid_t,
        applicationName: String
    ) {
        cancel()
        lastError = nil
        lastOutput = nil
        didCopyOutput = false
        lastNotice = nil
        targetApplication = UniversalActionTarget(
            bundleIdentifier: targetBundleIdentifier,
            processIdentifier: processIdentifier,
            applicationName: applicationName
        )
    }

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
        await readSelection(text, source: "clipboard")
    }

    /// Explicit user-requested copy. Unlike selection detection, this is never
    /// used as an invisible fallback.
    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        lastNotice = "Copied"
    }

    func saveSelection(_ text: String) {
        guard LocalLibraryStore.shared.saveText(text) != nil else {
            lastError = UniversalActionError.emptyInput
            return
        }
        lastError = nil
        lastNotice = "Saved to Library"
    }

    func saveURL(_ url: URL) {
        startContentTask { [weak self] in
            _ = try await LocalLibraryStore.shared.saveURL(url)
            self?.lastNotice = "Saved to Library"
        }
    }

    func readURL(_ url: URL) {
        let extract = self.extract
        startContentTask { [weak self] in
            let content = try await extract(url)
            guard let text = content.text,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ContentExtractionError.captionsUnavailable
            }
            self?.isProcessing = false
            InstantTTSService.shared.speak(text)
        }
    }

    func summarizeURL(_ url: URL) {
        let extract = self.extract
        let transform = self.transform
        startContentTask { [weak self] in
            let content = try await extract(url)
            guard let text = content.text,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ContentExtractionError.noReadableContent
            }
            let output = try await transform(
                text,
                "Summarize this clearly and accurately. Preserve important facts and names. Return only the summary."
            )
            self?.lastOutput = output
        }
    }

    func run(_ action: LocalTextAction, onURL url: URL) {
        let extract = self.extract
        let transform = self.transform
        startContentTask { [weak self] in
            let content = try await extract(url)
            guard let text = content.text,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ContentExtractionError.noReadableContent
            }
            self?.lastOutput = try await transform(text, action.prompt)
        }
    }

    func pasteLastDictation() {
        guard let text = DictationStore.shared.items.first?.polishedText, !text.isEmpty else {
            NSSound.beep()
            return
        }
        guard paste(text, nil) else {
            lastError = UniversalActionError.accessibilityRequired
            NSSound.beep()
            return
        }
    }

    /// Starts a cancellable provider request. Completion only updates preview
    /// state; it never writes to the focused application.
    func run(_ action: LocalTextAction, on text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = UniversalActionError.emptyInput
            return
        }

        actionTask?.cancel()
        let requestID = UUID()
        generationID = requestID
        isProcessing = true
        lastError = nil
        lastOutput = nil
        didCopyOutput = false
        lastNotice = nil
        let transform = self.transform

        actionTask = Task { [weak self] in
            do {
                let output = try await transform(text, action.prompt)
                try Task.checkCancellation()
                guard let self, self.generationID == requestID else { return }
                self.lastOutput = output
                self.isProcessing = false
                self.actionTask = nil
                self.generationID = nil
            } catch is CancellationError {
                guard let self, self.generationID == requestID else { return }
                self.isProcessing = false
                self.actionTask = nil
                self.generationID = nil
            } catch {
                guard let self, self.generationID == requestID else { return }
                self.lastError = error
                self.isProcessing = false
                self.actionTask = nil
                self.generationID = nil
            }
        }
    }

    func cancel() {
        generationID = nil
        actionTask?.cancel()
        actionTask = nil
        isProcessing = false
    }

    private func startContentTask(
        _ operation: @escaping @MainActor () async throws -> Void
    ) {
        actionTask?.cancel()
        let requestID = UUID()
        generationID = requestID
        isProcessing = true
        lastError = nil
        lastOutput = nil
        lastNotice = nil
        didCopyOutput = false
        actionTask = Task { [weak self] in
            do {
                try await operation()
                try Task.checkCancellation()
                guard let self, self.generationID == requestID else { return }
                self.isProcessing = false
                self.actionTask = nil
                self.generationID = nil
            } catch is CancellationError {
                guard let self, self.generationID == requestID else { return }
                self.isProcessing = false
                self.actionTask = nil
                self.generationID = nil
            } catch {
                guard let self, self.generationID == requestID else { return }
                self.lastError = error
                self.isProcessing = false
                self.actionTask = nil
                self.generationID = nil
            }
        }
    }

    @discardableResult
    func copyLastOutput() -> Bool {
        guard let output = lastOutput, !output.isEmpty else {
            lastError = UniversalActionError.noOutput
            return false
        }
        copy(output)
        lastError = nil
        didCopyOutput = true
        return true
    }

    /// Applies the preview only if focus is still in the application that
    /// opened Cmd+E. The explicit Apply button remains the final confirmation.
    @discardableResult
    func applyLastOutput() -> Bool {
        guard let output = lastOutput, !output.isEmpty else {
            lastError = UniversalActionError.noOutput
            return false
        }
        guard isAccessibilityReady() else {
            lastError = UniversalActionError.accessibilityRequired
            return false
        }
        guard let targetApplication else {
            lastError = UniversalActionError.originalApplicationUnavailable
            return false
        }
        guard Self.targetMatches(targetApplication, currentApplication()) else {
            lastError = UniversalActionError.targetApplicationChanged(
                targetApplication.applicationName
            )
            return false
        }
        guard paste(output, targetApplication) else {
            lastError = UniversalActionError.pasteFailed
            return false
        }
        lastError = nil
        return true
    }

    func clearResult() {
        lastError = nil
        lastOutput = nil
        didCopyOutput = false
        lastNotice = nil
    }

    static func targetMatches(
        _ expected: UniversalActionTarget,
        _ current: UniversalActionTarget?
    ) -> Bool {
        guard let current else { return false }
        return expected.processIdentifier == current.processIdentifier
            && (expected.bundleIdentifier.isEmpty
                || expected.bundleIdentifier == current.bundleIdentifier)
    }

    func openVibeRead() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { !($0 is NSPanel) })?.makeKeyAndOrderFront(nil)
    }
}
