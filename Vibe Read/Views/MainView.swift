import SwiftUI
import AppKit

private enum LocalAppTab: String, CaseIterable, Identifiable {
    case dictation = "Dictate"
    case read = "Read"
    case library = "Library"
    case actions = "Actions"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dictation: return "mic.fill"
        case .read: return "speaker.wave.2.fill"
        case .library: return "bookmark.fill"
        case .actions: return "wand.and.stars"
        }
    }
}

struct MainView: View {
    @ObservedObject private var tts = InstantTTSService.shared
    @State private var selection: LocalAppTab = .dictation
    @State private var isSidebarCollapsed = false
    @State private var showConfetti = false
    @State private var showingSettings = false
    @State private var settingsStartsOnProvider = false
    @State private var checkedProviderSetup = false

    var body: some View {
        ZStack {
            HStack(alignment: .top, spacing: 0) {
                LocalSidebarView(
                    isCollapsed: $isSidebarCollapsed,
                    selection: $selection,
                    showConfetti: $showConfetti,
                    onOpenSettings: openSettings
                )
                .frame(
                    width: isSidebarCollapsed ? 60 : AppTheme.Dimensions.sidebarWidth,
                    alignment: .leading
                )
                .clipped()

                ZStack(alignment: .bottom) {
                    AppTheme.Colors.contentBackground
                        .clipShape(RoundedRectangle(
                            cornerRadius: AppTheme.Dimensions.contentCornerRadius,
                            style: .continuous
                        ))
                        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)

                    contentViews
                        .clipShape(RoundedRectangle(
                            cornerRadius: AppTheme.Dimensions.contentCornerRadius,
                            style: .continuous
                        ))

                    if tts.isLoading || tts.isSpeaking || tts.isPaused {
                        InstantPlayerView()
                            .padding(20)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.trailing, AppTheme.Dimensions.contentPadding)
            }
            .padding(.vertical, AppTheme.Dimensions.contentPadding)

            ConfettiView(isActive: $showConfetti)
        }
        .tint(AppTheme.Colors.brandAccent)
        .background(AppTheme.Colors.sidebarBackground)
        .toolbarBackground(AppTheme.Colors.sidebarBackground, for: .windowToolbar)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSidebarCollapsed)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isSidebarCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(isSidebarCollapsed ? "Expand Sidebar" : "Collapse Sidebar")
                .accessibilityLabel(isSidebarCollapsed ? "Expand Sidebar" : "Collapse Sidebar")
            }

            ToolbarItem(placement: .automatic) {
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
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
        .onReceive(NotificationCenter.default.publisher(for: .showProviderSettings)) { _ in
            settingsStartsOnProvider = true
            showingSettings = true
        }
    }

    private func openSettings() {
        settingsStartsOnProvider = false
        showingSettings = true
    }

    private var contentViews: some View {
        ZStack {
            DictationView()
                .opacity(selection == .dictation ? 1 : 0)
                .allowsHitTesting(selection == .dictation)
                .accessibilityHidden(selection != .dictation)

            LocalReadView()
                .opacity(selection == .read ? 1 : 0)
                .allowsHitTesting(selection == .read)
                .accessibilityHidden(selection != .read)

            LocalLibraryView()
                .opacity(selection == .library ? 1 : 0)
                .allowsHitTesting(selection == .library)
                .accessibilityHidden(selection != .library)

            LocalActionsView()
                .opacity(selection == .actions ? 1 : 0)
                .allowsHitTesting(selection == .actions)
                .accessibilityHidden(selection != .actions)
        }
    }
}

private struct LocalSidebarView: View {
    @Binding var isCollapsed: Bool
    @Binding var selection: LocalAppTab
    @Binding var showConfetti: Bool
    let onOpenSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logoPressed = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: celebrate) {
                HStack(spacing: 10) {
                    Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .scaleEffect(logoPressed ? 0.9 : 1)

                    if !isCollapsed {
                        Text("Vibe Read")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .transition(.opacity.combined(with: .move(edge: .leading)))

                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, isCollapsed ? 0 : 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .help("Celebrate")
            .accessibilityLabel("Vibe Read logo")
            .accessibilityHint("Celebrate with confetti")

            VStack(spacing: 4) {
                ForEach(LocalAppTab.allCases) { tab in
                    LocalSidebarButton(
                        title: tab.rawValue,
                        icon: tab.icon,
                        isSelected: selection == tab,
                        isCollapsed: isCollapsed
                    ) {
                        selection = tab
                    }
                }
            }
            .padding(.horizontal, isCollapsed ? 12 : 10)

            Spacer()

            LocalSidebarButton(
                title: "Settings",
                icon: "gearshape",
                isSelected: false,
                isCollapsed: isCollapsed,
                action: onOpenSettings
            )
            .padding(.horizontal, isCollapsed ? 12 : 10)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.sidebarBackground)
    }

    private func celebrate() {
        showConfetti = false
        if !reduceMotion {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
                logoPressed = true
            }
        }
        DispatchQueue.main.async {
            showConfetti = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.58)) {
                logoPressed = false
            }
        }
    }
}

private struct LocalSidebarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let isCollapsed: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .frame(width: 20)

                if !isCollapsed {
                    Text(title)
                        .font(.system(size: 14, weight: isSelected ? .medium : .regular))
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .move(edge: .leading)))

                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: isCollapsed ? .center : .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(buttonBackground)
                    .shadow(
                        color: isSelected ? .black.opacity(0.07) : .clear,
                        radius: 1,
                        y: 1
                    )
            }
            .foregroundStyle(isSelected ? AppTheme.Colors.sidebarTextSelected : AppTheme.Colors.sidebarText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(isCollapsed ? title : "")
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var buttonBackground: Color {
        if isSelected { return AppTheme.Colors.contentBackground }
        if isHovered { return Color.primary.opacity(0.055) }
        return .clear
    }
}

struct LocalReadView: View {
    @ObservedObject private var tts = InstantTTSService.shared
    @EnvironmentObject private var settings: AppSettings
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Read aloud").font(.largeTitle.bold())
                Text(readAloudDescription)
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
                Button("Save to Library") {
                    _ = LocalLibraryStore.shared.saveText(text)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                if tts.isSpeaking || tts.isPaused {
                    Button("Stop", role: .destructive) { tts.stop() }
                }
                Button("Read") { tts.speak(text) }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let error = tts.error {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var readAloudDescription: String {
        settings.readAloudProvider == .elevenLabs
            ? "Reads with your ElevenLabs voice. Text goes directly to ElevenLabs when you press Read."
            : "Reads with a voice built into macOS. Text stays on this Mac."
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

            VStack(alignment: .leading, spacing: 10) {
                Text("Built-in actions").font(.headline)
                Text("Choose the useful actions that always appear before your custom prompts.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 10) {
                    ForEach(BuiltInPaletteAction.allCases) { action in
                        Toggle(isOn: Binding(
                            get: { store.isEnabled(action) },
                            set: { store.setEnabled($0, for: action) }
                        )) {
                            Label(action.name, systemImage: action.icon)
                        }
                        .toggleStyle(.button)
                    }
                }
            }
            .padding(14)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))

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
            if tts.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("Generating voice")
            } else {
                Button(action: tts.toggle) {
                    Image(systemName: tts.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.borderless)
            }

            Text(tts.isLoading ? "Generating voice" : (tts.currentText ?? "Reading"))
                .lineLimit(1)
                .font(.caption)
            Spacer()
            Button(action: tts.stop) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
    }
}

#Preview {
    MainView().environmentObject(AppSettings.shared)
}
