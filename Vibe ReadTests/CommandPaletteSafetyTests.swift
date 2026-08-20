import Carbon.HIToolbox
import Testing
@testable import Vibe_Read

struct CommandPaletteSafetyTests {
    @Test @MainActor func customActionStoreDeduplicatesPersistedActionsWithoutReordering() throws {
        let suiteName = "VibeReadTests.actions.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = LocalTextAction(
            name: "  Draft email  ",
            prompt: "  Write a concise reply.  "
        )
        let duplicate = LocalTextAction(
            name: "Draft email",
            prompt: "Write a concise reply."
        )
        let second = LocalTextAction(
            name: "Turn into bullets",
            prompt: "Return a short bullet list."
        )
        defaults.set(
            try JSONEncoder().encode([first, duplicate, second]),
            forKey: "localTextActions.v1"
        )

        let store = LocalTextActionStore(defaults: defaults)

        #expect(store.actions.map(\.id) == [first.id, second.id])
        #expect(store.actions.map(\.name) == ["Draft email", "Turn into bullets"])

        let persistedData = try #require(defaults.data(forKey: "localTextActions.v1"))
        let persisted = try JSONDecoder().decode([LocalTextAction].self, from: persistedData)
        #expect(persisted == store.actions)
    }

    @Test @MainActor func customActionEditorRejectsEmptyAndDuplicateActionsAndPreservesOrder() throws {
        let suiteName = "VibeReadTests.action-editor.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(try JSONEncoder().encode([LocalTextAction]()), forKey: "localTextActions.v1")

        let store = LocalTextActionStore(defaults: defaults)
        #expect(!store.save(id: nil, name: "", prompt: "Rewrite this"))
        #expect(!store.save(id: nil, name: "Rewrite", prompt: "   "))
        #expect(store.save(id: nil, name: " Rewrite ", prompt: " Make it clear. "))
        #expect(!store.save(id: nil, name: "Rewrite", prompt: "Make it clear."))
        #expect(store.save(id: nil, name: "Summarize", prompt: "Make it short."))

        let firstID = try #require(store.actions.first?.id)
        #expect(store.save(id: firstID, name: "Polish", prompt: "Make it clearer."))
        #expect(store.actions.map(\.name) == ["Polish", "Summarize"])
    }

    @Test func secondFnTransitionFinishesHandsFreeDictation() {
        #expect(
            KeyboardShortcutService.shouldFinishHandsFree(
                isHandsFreeRecording: true,
                shortcutAction: .handsFree
            )
        )
        #expect(
            !KeyboardShortcutService.shouldFinishHandsFree(
                isHandsFreeRecording: false,
                shortcutAction: .handsFree
            )
        )
        #expect(
            !KeyboardShortcutService.shouldFinishHandsFree(
                isHandsFreeRecording: true,
                shortcutAction: .pushToTalk
            )
        )
    }

    @Test func fnReleaseDoesNotSendASecondStopAfterPressHandledIt() {
        #expect(
            !KeyboardShortcutService.shouldFinishHandsFreeOnRelease(
                isHandsFreeRecording: true,
                shortcutAction: .handsFree,
                didTriggerOnPress: true
            )
        )
        #expect(
            KeyboardShortcutService.shouldFinishHandsFreeOnRelease(
                isHandsFreeRecording: true,
                shortcutAction: .handsFree,
                didTriggerOnPress: false
            )
        )
    }

    @Test func commandChordRoutesThroughCarbon() {
        let representation = KeyboardShortcutService.carbonRepresentation(
            for: [.command, .e]
        )

        #expect(representation?.keyCode == UInt32(KeyCode.e.cgKeyCode ?? 0))
        #expect((representation?.modifiers ?? 0) & UInt32(cmdKey) != 0)
    }

    @Test func fnChordsStayOnThePressReleasePath() {
        #expect(KeyboardShortcutService.carbonRepresentation(for: [.fn, .space]) == nil)
        #expect(KeyboardShortcutService.carbonRepresentation(for: [.fn]) == nil)
    }

    @Test func unsafeBareTypingKeysAreNotReservedGlobally() {
        #expect(KeyboardShortcutService.carbonRepresentation(for: [.e]) == nil)
        #expect(KeyboardShortcutService.carbonRepresentation(for: [.space]) == nil)
        #expect(KeyboardShortcutService.carbonRepresentation(for: [.f8]) != nil)
    }

    @Test func ambiguousMultiKeyCombosAreNotRegistered() {
        #expect(KeyboardShortcutService.carbonRepresentation(
            for: [.command, .e, .v]
        ) == nil)
        #expect(KeyboardShortcutService.carbonRepresentation(
            for: [.command, .shift]
        ) == nil)
    }

    @Test @MainActor func providerCompletionOnlyCreatesAPreview() async {
        let target = UniversalActionTarget(
            bundleIdentifier: "com.example.editor",
            processIdentifier: 42,
            applicationName: "Editor"
        )
        var pastedText: String?
        var pastedTarget: UniversalActionTarget?
        let service = UniversalActionService(
            transform: { _, _ in "Corrected text" },
            currentApplication: { target },
            isAccessibilityReady: { true },
            paste: { text, target in
                pastedText = text
                pastedTarget = target
                return true
            }
        )
        service.beginSession(
            targetBundleIdentifier: target.bundleIdentifier,
            processIdentifier: target.processIdentifier,
            applicationName: target.applicationName
        )

        service.run(
            LocalTextAction(name: "Correct", prompt: "Correct it"),
            on: "Input"
        )
        await waitUntilFinished(service)

        #expect(service.lastOutput == "Corrected text")
        #expect(pastedText == nil)

        #expect(service.applyLastOutput())
        #expect(pastedText == "Corrected text")
        #expect(pastedTarget == target)
    }

    @Test @MainActor func applyRefusesANewlyFocusedApplication() async {
        let original = UniversalActionTarget(
            bundleIdentifier: "com.example.notes",
            processIdentifier: 42,
            applicationName: "Notes"
        )
        let unrelated = UniversalActionTarget(
            bundleIdentifier: "com.example.mail",
            processIdentifier: 99,
            applicationName: "Mail"
        )
        var pasteCount = 0
        let service = UniversalActionService(
            transform: { _, _ in "Private output" },
            currentApplication: { unrelated },
            isAccessibilityReady: { true },
            paste: { _, _ in
                pasteCount += 1
                return true
            }
        )
        service.beginSession(
            targetBundleIdentifier: original.bundleIdentifier,
            processIdentifier: original.processIdentifier,
            applicationName: original.applicationName
        )
        service.run(
            LocalTextAction(name: "Rewrite", prompt: "Rewrite it"),
            on: "Input"
        )
        await waitUntilFinished(service)

        #expect(!service.applyLastOutput())
        #expect(pasteCount == 0)
        #expect(
            service.lastError as? UniversalActionError
                == .targetApplicationChanged("Notes")
        )
    }

    @Test @MainActor func cancelledAndStaleGenerationsCannotReplacePreview() async {
        let target = UniversalActionTarget(
            bundleIdentifier: "com.example.editor",
            processIdentifier: 42,
            applicationName: "Editor"
        )
        let service = UniversalActionService(
            transform: { text, _ in
                if text == "first" {
                    do {
                        try await Task.sleep(nanoseconds: 30_000_000)
                    } catch {
                        // Deliberately ignore cancellation to exercise the
                        // service's generation guard.
                    }
                    return "stale"
                }
                return "fresh"
            },
            currentApplication: { target },
            isAccessibilityReady: { true },
            paste: { _, _ in true }
        )
        service.beginSession(
            targetBundleIdentifier: target.bundleIdentifier,
            processIdentifier: target.processIdentifier,
            applicationName: target.applicationName
        )
        let action = LocalTextAction(name: "Rewrite", prompt: "Rewrite it")

        service.run(action, on: "first")
        await Task.yield()
        service.run(action, on: "second")
        await waitUntilFinished(service)
        try? await Task.sleep(nanoseconds: 40_000_000)

        #expect(service.lastOutput == "fresh")
        #expect(!service.isProcessing)

        service.run(action, on: "first")
        service.cancel()
        try? await Task.sleep(nanoseconds: 40_000_000)
        #expect(!service.isProcessing)
        #expect(service.lastOutput == nil)
    }

    @MainActor
    private func waitUntilFinished(_ service: UniversalActionService) async {
        for _ in 0..<200 {
            if !service.isProcessing { return }
            await Task.yield()
        }
    }
}
