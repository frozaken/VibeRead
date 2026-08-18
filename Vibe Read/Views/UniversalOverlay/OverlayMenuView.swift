import SwiftUI
import AppKit

struct OverlayMenuView: View {
    @ObservedObject var controller: UniversalOverlayController
    @ObservedObject private var actionService = UniversalActionService.shared
    @ObservedObject private var actionStore = LocalTextActionStore.shared
    @State private var selectedIndex = 0
    @State private var hoveringIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().padding(.horizontal, 12)

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

            if actionService.isProcessing {
                Divider().padding(.horizontal, 12)
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Running with your provider…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
            } else if let error = actionService.lastError {
                Divider().padding(.horizontal, 12)
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
                    .padding(8)
            }
        }
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .focusable()
        .modifier(OverlayKeyboardNavigation(
            onUp: { move(by: -1) },
            onDown: { move(by: 1) },
            onEnter: {
                if menuItems.indices.contains(selectedIndex) {
                    execute(menuItems[selectedIndex])
                }
            }
        ))
    }

    private var sourceText: String? {
        if let selected = controller.currentContext?.selectedText,
           !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return selected
        }
        if case .clipboard = controller.currentContext?.contextType,
           let clipboard = NSPasteboard.general.string(forType: .string),
           !clipboard.isEmpty {
            return clipboard
        }
        return nil
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: sourceText == nil ? "command" : "text.cursor")
                    .foregroundColor(.secondary)
                Text(sourceText == nil ? "Vibe Read actions" : "Selected text")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(actionPaletteShortcut)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Button(action: controller.hide) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
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
            items.append(MenuItem(
                id: "read",
                icon: "speaker.wave.2.fill",
                title: "Read aloud",
                action: { Task { await actionService.readSelection(text) } }
            ))
            items.append(MenuItem(
                id: "copy",
                icon: "doc.on.doc",
                title: "Copy",
                action: { actionService.copy(text) }
            ))

            if !actionStore.actions.isEmpty {
                items.append(.separator(id: "ai-separator"))
                for action in actionStore.actions {
                    items.append(MenuItem(
                        id: action.id.uuidString,
                        icon: "wand.and.stars",
                        title: action.name,
                        action: { Task { await actionService.run(action, on: text) } }
                    ))
                }
            }
        } else {
            items.append(MenuItem(
                id: "hint",
                icon: "info.circle",
                title: "Select text, then open this palette",
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
        guard !item.isSeparator && !item.isDisabled else { return }
        controller.hide()
        item.action()
    }

    private func move(by delta: Int) {
        let valid = menuItems.enumerated().filter { !$0.element.isSeparator && !$0.element.isDisabled }
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
