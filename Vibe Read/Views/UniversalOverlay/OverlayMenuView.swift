import SwiftUI
import AppKit

struct OverlayMenuView: View {
    @ObservedObject var controller: UniversalOverlayController
    @ObservedObject private var actionService = UniversalActionService.shared
    @ObservedObject private var actionStore = LocalTextActionStore.shared
    @ObservedObject private var accessibility = AccessibilityService.shared
    @State private var selectedIndex = 0
    @State private var hoveringIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().padding(.horizontal, 12)

            if !accessibility.hasAccessibilityPermission {
                accessibilityBanner
                Divider().padding(.horizontal, 12)
            }

            Group {
                if actionService.isProcessing {
                    processingView
                } else if actionService.lastOutput != nil {
                    resultView
                } else if actionService.lastNotice != nil {
                    noticeView
                } else {
                    actionList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The controller sizes the nonactivating panel only when it opens.
        // A stable canvas prevents async progress and output from being clipped.
        .frame(width: 280, height: 400)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        )
        .focusable()
        .modifier(OverlayKeyboardNavigation(
            onUp: { move(by: -1) },
            onDown: { move(by: 1) },
            onEnter: {
                guard !actionService.isProcessing,
                      actionService.lastOutput == nil,
                      menuItems.indices.contains(selectedIndex) else { return }
                execute(menuItems[selectedIndex])
            }
        ))
        .task(id: actionService.isProcessing) {
            guard actionService.isProcessing else { return }
            while !Task.isCancelled && actionService.isProcessing {
                controller.resetDismissTimer()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
        .onReceive(actionService.$lastOutput) { output in
            if output != nil { controller.resetDismissTimer() }
        }
        .onChange(of: controller.isVisible) { isVisible in
            if !isVisible && actionService.isProcessing {
                actionService.cancel()
            }
        }
    }

    private var actionList: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(menuItems.enumerated()), id: \.element.id) { index, item in
                        MenuItemRow(
                            item: item,
                            isSelected: selectedIndex == index,
                            isHovering: hoveringIndex == index
                        )
                        .onTapGesture { execute(item) }
                        .onHover { hovering in
                            hoveringIndex = hovering ? index : nil
                            if hovering { selectedIndex = index }
                            controller.resetDismissTimer()
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            if let error = actionService.lastError {
                Divider().padding(.horizontal, 12)
                errorText(error)
                    .padding(10)
            }
        }
    }

    private var processingView: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)
            ThinkingOrbView(size: 58)
                .accessibilityLabel("Running text action")
            Text("Running with your provider")
                .font(.system(size: 13, weight: .medium))
            Text("The result will stay here for review.")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Cancel") {
                actionService.cancel()
            }
            .keyboardShortcut(.cancelAction)
            Spacer(minLength: 8)
        }
        .padding(16)
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Preview", systemImage: "text.page")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Discard") {
                    actionService.clearResult()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.secondary)
            }

            ScrollView {
                Text(actionService.lastOutput ?? "")
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.055))
            )

            if let error = actionService.lastError {
                errorText(error)
            }

            HStack(spacing: 8) {
                Button {
                    _ = actionService.copyLastOutput()
                    controller.resetDismissTimer()
                } label: {
                    Label(
                        actionService.didCopyOutput ? "Copied" : "Copy",
                        systemImage: actionService.didCopyOutput ? "checkmark" : "doc.on.doc"
                    )
                }

                Spacer()

                Button {
                    if actionService.applyLastOutput() {
                        controller.hide()
                    } else {
                        controller.resetDismissTimer()
                    }
                } label: {
                    Label("Apply", systemImage: "arrow.turn.down.left")
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(12)
    }

    private var noticeView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.green)
            Text(actionService.lastNotice ?? "Done")
                .font(.headline)
            Button("Done") { controller.hide() }
            Spacer()
        }
    }

    private var accessibilityBanner: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "accessibility")
                    .foregroundColor(.orange)
                Text("Turn on Vibe Read in System Settings for selection, Fn shortcuts, and Apply. Cmd+E and clipboard actions still work.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button("Request Accessibility") {
                    accessibility.requestAccessibilityPermission()
                }
                Button("Open Settings") {
                    accessibility.openAccessibilitySettings()
                }
                Spacer()
                Button {
                    accessibility.refreshAllPermissions()
                } label: {
                    Image(systemName: accessibility.isPollingForPermission
                        ? "hourglass"
                        : "arrow.clockwise")
                }
                .help("Check permission again")
                .accessibilityLabel("Check Accessibility permission again")
            }
            .buttonStyle(.plain)
            .font(.caption2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func errorText(_ error: Error) -> some View {
        Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
            .font(.caption2)
            .foregroundColor(.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var sourceText: String? {
        guard let snapshot = controller.currentContext?.selectedText,
              !snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return snapshot
    }

    private var sourceURL: URL? {
        controller.currentContext?.browserURL
            ?? sourceText.flatMap(ContentExtractionService.normalizedWebURL(from:))
    }

    private var sourceLabel: String {
        switch controller.currentContext?.contextType {
        case .browser(let url):
            return ContentExtractionService.kind(for: url).displayName
        case .textSelection: return "Selected text"
        case .clipboard: return "Copied clipboard text"
        default: return "Vibe Read actions"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: sourceText == nil ? "command" : "text.cursor")
                    .foregroundColor(.secondary)
                Text(sourceLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(actionPaletteShortcut)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Button {
                    actionService.cancel()
                    controller.hide()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close action palette")
            }

            if let text = sourceText {
                Text(String(text.prefix(80)) + (text.count > 80 ? "…" : ""))
                    .font(.caption2)
                    .foregroundColor(.primary.opacity(0.7))
                    .lineLimit(2)
            }
        }
        .padding(12)
    }

    private var actionPaletteShortcut: String {
        AppSettings.shared.primaryShortcut(for: .openActionPalette)?.keys
            .map { key in
                switch key {
                case .command: return "⌘"
                case .shift: return "⇧"
                case .option: return "⌥"
                case .control: return "⌃"
                case .fn: return "fn"
                case .space: return "Space"
                default: return key.rawValue
                }
            }
            .joined() ?? ""
    }

    private var menuItems: [MenuItem] {
        var items: [MenuItem] = []
        if let text = sourceText {
            let url = sourceURL
            if actionStore.isEnabled(.readAloud) {
                items.append(MenuItem(
                    id: "read",
                    icon: BuiltInPaletteAction.readAloud.icon,
                    title: url == nil ? "Read aloud" : "Read this page",
                    keepsOpen: url != nil,
                    action: {
                        if let url { actionService.readURL(url) }
                        else { Task { await actionService.readSelection(text) } }
                    }
                ))
            }
            if actionStore.isEnabled(.saveToLibrary) {
                items.append(MenuItem(
                    id: "save",
                    icon: BuiltInPaletteAction.saveToLibrary.icon,
                    title: "Save to Library",
                    keepsOpen: true,
                    action: {
                        if let url { actionService.saveURL(url) }
                        else { actionService.saveSelection(text) }
                    }
                ))
            }
            if actionStore.isEnabled(.summarize) {
                let summarize = LocalTextAction(
                    name: "Summarize",
                    prompt: "Summarize this clearly and accurately. Preserve important facts and names. Return only the summary."
                )
                items.append(MenuItem(
                    id: "summarize",
                    icon: BuiltInPaletteAction.summarize.icon,
                    title: url == nil ? "Summarize" : "Summarize this page",
                    keepsOpen: true,
                    action: {
                        if let url { actionService.summarizeURL(url) }
                        else { actionService.run(summarize, on: text) }
                    }
                ))
            }
            if actionStore.isEnabled(.copy) {
                items.append(MenuItem(
                    id: "copy",
                    icon: BuiltInPaletteAction.copy.icon,
                    title: "Copy",
                    keepsOpen: true,
                    action: { actionService.copy(text) }
                ))
            }

            if !actionStore.actions.isEmpty {
                items.append(.separator(id: "ai-separator"))
                for action in actionStore.actions {
                    items.append(MenuItem(
                        id: action.id.uuidString,
                        icon: "wand.and.stars",
                        title: action.name,
                        keepsOpen: true,
                        action: {
                            if let url { actionService.run(action, onURL: url) }
                            else { actionService.run(action, on: text) }
                        }
                    ))
                }
            }
        } else {
            items.append(MenuItem(
                id: "hint",
                icon: "info.circle",
                title: accessibility.hasAccessibilityPermission
                    ? "Select text, then open this palette"
                    : "Grant access to use selected text",
                isDisabled: true,
                action: {}
            ))
        }

        items.append(.separator(id: "utility-separator"))
        items.append(MenuItem(
            id: "paste-last",
            icon: "text.badge.plus",
            title: "Paste last dictation",
            action: actionService.pasteLastDictation
        ))
        items.append(.openVibeRead)
        return items
    }

    private func execute(_ item: MenuItem) {
        guard !actionService.isProcessing,
              !item.isSeparator,
              !item.isDisabled else { return }
        if item.keepsOpen {
            item.action()
            controller.resetDismissTimer()
        } else {
            controller.hide()
            item.action()
        }
    }

    private func move(by delta: Int) {
        guard !actionService.isProcessing,
              actionService.lastOutput == nil,
              actionService.lastNotice == nil else { return }
        let valid = menuItems.enumerated().filter {
            !$0.element.isSeparator && !$0.element.isDisabled
        }
        guard !valid.isEmpty else { return }
        let current = valid.firstIndex(where: { $0.offset == selectedIndex }) ?? 0
        selectedIndex = valid[(current + delta + valid.count) % valid.count].offset
        controller.resetDismissTimer()
    }
}

private struct OverlayKeyboardNavigation: ViewModifier {
    let onUp: () -> Void
    let onDown: () -> Void
    let onEnter: () -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .onKeyPress(.upArrow) { onUp(); return .handled }
                .onKeyPress(.downArrow) { onDown(); return .handled }
                .onKeyPress(.return) { onEnter(); return .handled }
        } else {
            content.background(
                OverlayKeyboardMonitor(onUp: onUp, onDown: onDown, onEnter: onEnter)
            )
        }
    }
}

private struct OverlayKeyboardMonitor: NSViewRepresentable {
    let onUp: () -> Void
    let onDown: () -> Void
    let onEnter: () -> Void

    func makeNSView(context: Context) -> OverlayKeyboardView {
        let view = OverlayKeyboardView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: OverlayKeyboardView, context: Context) {
        view.onUp = onUp
        view.onDown = onDown
        view.onEnter = onEnter
    }
}

private final class OverlayKeyboardView: NSView {
    var onUp: (() -> Void)?
    var onDown: (() -> Void)?
    var onEnter: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: onUp?()
        case 125: onDown?()
        case 36: onEnter?()
        default: super.keyDown(with: event)
        }
    }
}

struct MenuItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    var shortcut: String? = nil
    var isDisabled = false
    var isSeparator = false
    var keepsOpen = false
    let action: () -> Void

    static func separator(id: String) -> MenuItem {
        MenuItem(id: id, icon: "", title: "", isSeparator: true, action: {})
    }

    static let openVibeRead = MenuItem(
        id: "open-app",
        icon: "waveform",
        title: "Open Vibe Read",
        action: {
            Task { @MainActor in
                UniversalActionService.shared.openVibeRead()
            }
        }
    )
}

struct MenuItemRow: View {
    let item: MenuItem
    let isSelected: Bool
    let isHovering: Bool

    var body: some View {
        if item.isSeparator {
            Divider().padding(.horizontal, 12).padding(.vertical, 4)
        } else {
            HStack(spacing: 10) {
                Image(systemName: item.icon).frame(width: 20)
                Text(item.title).font(.system(size: 13))
                Spacer()
                if let shortcut = item.shortcut {
                    Text(shortcut).font(.caption2).foregroundColor(.secondary)
                }
            }
            .foregroundColor(item.isDisabled ? .secondary : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected || isHovering ? Color.accentColor.opacity(0.15) : .clear)
            )
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .opacity(item.isDisabled ? 0.5 : 1)
        }
    }
}
