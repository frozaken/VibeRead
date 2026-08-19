import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab

    private enum Tab: String, CaseIterable, Identifiable {
        case general = "General"
        case provider = "AI Provider"
        case shortcuts = "Shortcuts"
        case storage = "Local Data"
        case about = "About"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general: return "gear"
            case .provider: return "key"
            case .shortcuts: return "keyboard"
            case .storage: return "internaldrive"
            case .about: return "info.circle"
            }
        }
    }

    init(startsOnProvider: Bool = false) {
        _tab = State(initialValue: startsOnProvider ? .provider : .general)
    }

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, selection: $tab) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .navigationTitle("Settings")
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    Text(tab.rawValue).font(.title2.bold())
                    Spacer()
                    Button(action: dismiss.callAsFunction) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(24)

                Divider()
                ScrollView {
                    Group {
                        switch tab {
                        case .general: LocalGeneralSettings()
                        case .provider: ProviderConfigurationSettingsView()
                        case .shortcuts: LocalShortcutSettings()
                        case .storage: LocalDataSettingsView()
                        case .about: LocalAboutSettings()
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(width: 880, height: 700)
        .onAppear {
            if AIProviderSettings.shared.needsDictationSetup {
                tab = .provider
            }
        }
    }
}

private struct LocalGeneralSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var accessibility = AccessibilityService.shared
    private let voices = InstantTTSService.availableVoices

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: "Accessibility") {
                Label(
                    accessibility.hasAccessibilityPermission
                        ? "Accessibility access granted"
                        : "Selected text, function-key shortcuts, and pasting need access",
                    systemImage: accessibility.hasAccessibilityPermission
                        ? "checkmark.circle.fill"
                        : "accessibility"
                )
                .foregroundColor(accessibility.hasAccessibilityPermission ? .green : .secondary)

                if !accessibility.hasAccessibilityPermission {
                    HStack {
                        Button("Grant Access") {
                            accessibility.requestAccessibilityPermission()
                        }
                        Button("Open System Settings") {
                            accessibility.openAccessibilitySettings()
                        }
                        Button("Check Again") {
                            accessibility.refreshAllPermissions()
                        }
                        .disabled(accessibility.isPollingForPermission)
                    }
                }

                Text("Ordinary global shortcuts such as Cmd + E work without Accessibility. The app asks only for the features that need it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            SettingsSection(title: "Dictation") {
                Toggle("Paste after dictation", isOn: $settings.autoPasteAfterDictation)
                Toggle("Sound effects", isOn: $settings.dictationSoundEffectsEnabled)
            }

            SettingsSection(title: "Local read-aloud") {
                Picker("macOS voice", selection: $settings.preferredVoiceId) {
                    ForEach(voices, id: \.identifier) { voice in
                        Text("\(voice.name) · \(voice.language)").tag(voice.identifier)
                    }
                }
                HStack {
                    Text("Speed")
                    Slider(value: $settings.voiceSpeed, in: 0.6...1.8, step: 0.05)
                    Text(String(format: "%.2fx", settings.voiceSpeed)).monospacedDigit()
                }
                Button("Preview voice") {
                    InstantTTSService.shared.previewVoice(voiceId: settings.preferredVoiceId)
                }
            }

            SettingsSection(title: "Appearance") {
                Picker("Theme", selection: $settings.themeMode) {
                    Text("System").tag(ThemeMode.system)
                    Text("Light").tag(ThemeMode.light)
                    Text("Dark").tag(ThemeMode.dark)
                }
                .pickerStyle(.segmented)
            }
        }
        .onAppear {
            if !voices.contains(where: { $0.identifier == settings.preferredVoiceId }),
               let defaultVoice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en")
                    ?? voices.first {
                settings.preferredVoiceId = defaultVoice.identifier
            }
        }
    }
}

private struct LocalShortcutSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var shortcutService = KeyboardShortcutService.shared
    @State private var editingAction: ShortcutAction?
    @State private var editingShortcutID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("All shortcuts are stored locally. Cmd+E is an ordinary action and can be rebound here.")
                .foregroundColor(.secondary)

            ForEach(shortcutService.shortcutRegistrationFailures.keys.sorted(), id: \.self) { action in
                if let message = shortcutService.shortcutRegistrationFailures[action] {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            ForEach(ShortcutAction.allCases) { action in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(action.displayName).font(.headline)
                        Text(action.description).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(settings.primaryShortcut(for: action)?.displayString ?? "Not set")
                        .font(.system(.body, design: .monospaced))
                    Button("Change") {
                        editingAction = action
                        editingShortcutID = settings.primaryShortcut(for: action)?.id
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Button("Reset Shortcuts") { settings.resetShortcutsToDefault() }
        }
        .sheet(item: $editingAction) { action in
            ShortcutEditorSheet(action: action, existingShortcutId: editingShortcutID)
                .environmentObject(settings)
                .dismissableSheet()
        }
    }
}

private struct LocalDataSettingsView: View {
    @ObservedObject private var store = DictationStore.shared
    @State private var confirmingClearHistory = false
    @State private var confirmingClearAudio = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: "Audio retention") {
                Picker("Delete recordings", selection: Binding(
                    get: { store.audioRetention },
                    set: { store.audioRetention = $0 }
                )) {
                    ForEach(DictationStore.AudioRetention.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Text(audioRetentionExplanation)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            SettingsSection(title: "Storage") {
                Button("Open Dictations Folder") {
                    if let url = DictationStore.dictationsDirectory { NSWorkspace.shared.open(url) }
                }
                Button("Delete All Audio…", role: .destructive) { confirmingClearAudio = true }
                Button("Delete All History and Audio…", role: .destructive) { confirmingClearHistory = true }
            }

            Label("History is stored in Application Support/VibeRead/dictations.sqlite3. Nothing is synced.", systemImage: "internaldrive")
                .font(.caption)
                .foregroundColor(.secondary)

            if let persistenceError = store.persistenceError {
                Label(persistenceError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmationDialog("Delete all retained audio?", isPresented: $confirmingClearAudio) {
            Button("Delete Audio", role: .destructive) { store.deleteAllAudio() }
        }
        .confirmationDialog("Delete all dictation history and audio?", isPresented: $confirmingClearHistory) {
            Button("Delete Everything", role: .destructive) { store.clearAll() }
        }
    }

    private var audioRetentionExplanation: String {
        switch store.audioRetention {
        case .immediately:
            return "Audio is deleted as soon as its history row is saved. Failed recordings cannot be retried. Transcripts remain until you delete them."
        case .oneDay:
            return "Audio is kept for one day so failed recordings can be retried. Transcripts remain until you delete them."
        case .sevenDays:
            return "Audio is kept for seven days by default so failed recordings can be retried. Transcripts remain until you delete them."
        case .thirtyDays:
            return "Audio is kept for thirty days so failed recordings can be retried. Transcripts remain until you delete them."
        case .never:
            return "Audio and transcripts remain on this Mac until you delete them."
        }
    }
}

private struct LocalAboutSettings: View {
    private let sourceURL = URL(string: "https://github.com/mathias-heide/VibeRead")!

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development"
    }

    private var build: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable().frame(width: 64, height: 64)
            Text("Vibe Read").font(.title.bold())
            Text(build.map { "Version \(version) (\($0))" } ?? "Version \(version)")
                .foregroundColor(.secondary)
            Text("A small, local-first macOS app for dictation, read-aloud, and rebindable text actions. No accounts, subscriptions, analytics, or Vibe Read cloud.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Vibe Read never checks for updates in the background. Open-source builds are updated by pulling the repository and rebuilding locally.")
                .font(.caption)
                .foregroundColor(.secondary)
            Link("Source & Updates", destination: sourceURL)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 12) { content }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
