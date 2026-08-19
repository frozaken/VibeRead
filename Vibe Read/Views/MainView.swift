import SwiftUI
import AppKit

private enum LocalAppTab: String, CaseIterable, Identifiable {
    case dictation = "Dictate"
    case read = "Read"
    case actions = "Actions"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dictation: return "mic.fill"
        case .read: return "speaker.wave.2.fill"
        case .actions: return "wand.and.stars"
        }
    }
}

struct MainView: View {
    @ObservedObject private var tts = InstantTTSService.shared
    @State private var selection: LocalAppTab? = .dictation
    @State private var showingSettings = false
    @State private var settingsStartsOnProvider = false
    @State private var checkedProviderSetup = false

    var body: some View {
        NavigationSplitView {
            List(LocalAppTab.allCases, selection: $selection) { tab in
                Label(tab.rawValue, systemImage: tab.icon).tag(tab)
            }
            .navigationTitle("Vibe Read")
            .safeAreaInset(edge: .bottom) {
                Button(action: {
                    settingsStartsOnProvider = false
                    showingSettings = true
                }) {
                    Label("Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding()
            }
        } detail: {
            ZStack(alignment: .bottom) {
                switch selection ?? .dictation {
                case .dictation: DictationView()
                case .read: LocalReadView()
                case .actions: LocalActionsView()
                }

                if tts.isSpeaking || tts.isPaused {
                    InstantPlayerView().padding()
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(startsOnProvider: settingsStartsOnProvider)
                .dismissableSheet()
        }
        .onAppear {
            guard !checkedProviderSetup else { return }
            checkedProviderSetup = true
            if AIProviderSettings.shared.needsDictationSetup {
                settingsStartsOnProvider = true
                showingSettings = true
            }
        }
    }
}

struct LocalReadView: View {
    @ObservedObject private var tts = InstantTTSService.shared
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Read aloud").font(.largeTitle.bold())
                Text("Uses the voices built into macOS. Your text stays on this Mac.")
                    .foregroundColor(.secondary)
            }

            TextEditor(text: $text)
                .font(.body)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))

            HStack {
                Button("Paste from Clipboard") {
                    text = NSPasteboard.general.string(forType: .string) ?? ""
                }
                Spacer()
                if tts.isSpeaking || tts.isPaused {
                    Button("Stop", role: .destructive) { tts.stop() }
                }
                Button("Read") { tts.speak(text) }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LocalActionsView: View {
    @ObservedObject private var store = LocalTextActionStore.shared
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Cmd+E actions").font(.largeTitle.bold())
                    Text("Edit the prompts shown over selected text. They use only your configured provider.")
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Add Action") { store.add() }
                    .buttonStyle(.borderedProminent)
            }

            List {
                ForEach($store.actions) { $action in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Action name", text: $action.name)
                            .font(.headline)
                        TextEditor(text: $action.prompt)
                            .frame(minHeight: 58)
                            .font(.callout)
                    }
                    .padding(.vertical, 8)
                }
                .onDelete(perform: store.remove)
            }
            .listStyle(.inset)

            HStack {
                Text("Shortcut: \(paletteShortcut)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Reset Actions") { store.reset() }
            }
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var paletteShortcut: String {
        settings.primaryShortcut(for: .openActionPalette)?.displayString ?? "Not set"
    }
}

struct InstantPlayerView: View {
    @ObservedObject private var tts = InstantTTSService.shared

    var body: some View {
        HStack(spacing: 14) {
            Button(action: tts.toggle) {
                Image(systemName: tts.isPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.borderless)

            Text(tts.currentText ?? "Reading")
                .lineLimit(1)
                .font(.caption)
            Spacer()
            Button(action: tts.stop) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 4)
    }
}

#Preview {
    MainView().environmentObject(AppSettings.shared)
}
