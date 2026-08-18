import SwiftUI
import Combine
import AppKit

@MainActor
final class AppState: ObservableObject {
    let settings = AppSettings.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
}

@main
struct VibeReadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState.settings)
                .preferredColorScheme(colorScheme)
                .frame(minWidth: 840, minHeight: 580)
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .pasteboard) {
                Button("Read Clipboard") {
                    if let text = NSPasteboard.general.string(forType: .string) {
                        InstantTTSService.shared.speak(text)
                    }
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView().environmentObject(appState.settings)
        }
    }

    private var colorScheme: ColorScheme? {
        switch appState.settings.themeMode {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

@MainActor
final class StatusBarController: NSObject {
    static let shared = StatusBarController()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Vibe Read")
        rebuildMenu()

        InstantTTSService.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.rebuildMenu() } }
            .store(in: &cancellables)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        if InstantTTSService.shared.isSpeaking || InstantTTSService.shared.isPaused {
            let toggle = NSMenuItem(
                title: InstantTTSService.shared.isPaused ? "Resume" : "Pause",
                action: #selector(toggleReading),
                keyEquivalent: ""
            )
            toggle.target = self
            menu.addItem(toggle)
            let stop = NSMenuItem(title: "Stop", action: #selector(stopReading), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
            menu.addItem(.separator())
        }
        let show = NSMenuItem(title: "Show Vibe Read", action: #selector(showApp), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func showApp() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { !($0 is NSPanel) })?.makeKeyAndOrderFront(nil)
    }
    @objc private func toggleReading() { InstantTTSService.shared.toggle() }
    @objc private func stopReading() { InstantTTSService.shared.stop() }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shortcutService: KeyboardShortcutService?
    private var statusBarController: StatusBarController?
    private var overlayController: UniversalOverlayController?
    private var floatingHUD: FloatingHUDController?
    private var audioCleanupTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests import the app target. Do not register global shortcuts,
        // create status UI, or touch the user's real local history in that host.
        guard !DictationStore.isRunningTests else { return }

        setupShortcuts()
        statusBarController = .shared
        overlayController = .shared
        floatingHUD = .shared
        DictationStore.shared.cleanupExpiredAudio()
        audioCleanupTimer = Timer.scheduledTimer(
            timeInterval: 24 * 60 * 60,
            target: self,
            selector: #selector(cleanupExpiredAudio),
            userInfo: nil,
            repeats: true
        )
        audioCleanupTimer?.tolerance = 60 * 60

        if !AccessibilityService.shared.checkPermission() {
            print("[App] Accessibility permission is needed for global shortcuts and pasting")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        audioCleanupTimer?.invalidate()
        shortcutService?.stopMonitoring()
        InstantTTSService.shared.stop()
    }

    @objc private func cleanupExpiredAudio() {
        DictationStore.shared.cleanupExpiredAudio()
    }

    private func setupShortcuts() {
        let service = KeyboardShortcutService.shared
        shortcutService = service

        service.onPushToTalkStart = {
            Task { @MainActor in DictationService.shared.startPushToTalk() }
        }
        service.onPushToTalkEnd = {
            Task { @MainActor in DictationService.shared.endPushToTalk() }
        }
        service.onShortcutTriggered = { action in
            Task { @MainActor in
                switch action {
                case .handsFree:
                    DictationService.shared.toggleHandsFree()
                case .pushToTalk:
                    break
                case .commandMode:
                    DictationService.shared.toggleCommandMode()
                case .pasteLastTranscript:
                    UniversalActionService.shared.pasteLastDictation()
                case .openActionPalette:
                    Self.toggleActionPalette()
                case .readSelection:
                    Self.readSelection()
                case .toggleReadAloud:
                    InstantTTSService.shared.toggle()
                }
            }
        }
        service.startMonitoring()
    }

    static func readSelection() {
        let text = AccessibilityService.shared.getSelectedText()
            ?? NSPasteboard.general.string(forType: .string)
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            return
        }
        InstantTTSService.shared.speak(text)
    }

    static func toggleActionPalette(prefilledText: String? = nil) {
        if UniversalOverlayController.shared.isVisible {
            UniversalOverlayController.shared.hide()
            return
        }

        let selectedText = prefilledText ?? AccessibilityService.shared.getSelectedText()
        let hasSelection = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasClipboard = NSPasteboard.general.string(forType: .string)?.isEmpty == false
        let frontmost = NSWorkspace.shared.frontmostApplication
        let context = AppContext(
            frontmostApp: AppInfo(
                name: frontmost?.localizedName ?? "Unknown",
                bundleId: frontmost?.bundleIdentifier ?? ""
            ),
            selectedText: hasSelection ? selectedText : nil,
            browserURL: nil,
            documentPath: nil,
            emailContent: nil,
            contextType: hasSelection ? .textSelection : (hasClipboard ? .clipboard : .empty),
            needsPermission: false
        )
        UniversalOverlayController.shared.show(with: context)
    }
}

extension Notification.Name {
    static let pasteFromClipboard = Notification.Name("pasteFromClipboard")
    static let readSelectedText = Notification.Name("readSelectedText")
}
