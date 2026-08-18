import SwiftUI

struct ShortcutEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var shortcutService = KeyboardShortcutService.shared

    let action: ShortcutAction
    let existingShortcutId: UUID?

    @State private var recordedKeys: [KeyCode] = []
    @State private var isRecording = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Change Shortcut").font(.title2.bold())
                    Text(action.displayName).foregroundColor(.secondary)
                }
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }

            Button(action: startRecording) {
                HStack(spacing: 8) {
                    if recordedKeys.isEmpty {
                        Text(isRecording ? "Press up to 3 keys…" : "Click, then press your shortcut")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(recordedKeys, id: \.self) { key in
                            Text(key.displayName)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 70)
                .background(isRecording ? Color.accentColor.opacity(0.1) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isRecording ? Color.accentColor : Color.primary.opacity(0.2), lineWidth: isRecording ? 2 : 1)
                )
            }
            .buttonStyle(.plain)

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundColor(.red)
            }

            HStack {
                Button("Cancel", action: close)
                Spacer()
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(recordedKeys.isEmpty || recordedKeys.count > CustomKeyboardShortcut.maxKeys)
            }
        }
        .padding(24)
        .frame(width: 440, height: 280)
        .onAppear {
            if let existingShortcutId,
               let shortcut = settings.shortcuts.first(where: { $0.id == existingShortcutId }) {
                recordedKeys = shortcut.keys
            }
        }
        .onReceive(shortcutService.$recordedKeys) { keys in
            guard isRecording, !keys.isEmpty else { return }
            recordedKeys = Array(keys.prefix(CustomKeyboardShortcut.maxKeys))
            errorMessage = keys.count > CustomKeyboardShortcut.maxKeys ? "Maximum 3 keys" : nil
        }
    }

    private func startRecording() {
        isRecording = true
        errorMessage = nil
        shortcutService.startRecording()
    }

    private func save() {
        _ = shortcutService.stopRecording()
        isRecording = false

        let result: Result<Void, ShortcutError>
        if let existingShortcutId,
           var existing = settings.shortcuts.first(where: { $0.id == existingShortcutId }) {
            existing.keys = recordedKeys
            result = settings.updateShortcut(existing)
        } else {
            result = settings.addShortcut(CustomKeyboardShortcut(keys: recordedKeys, action: action))
        }

        if let error = result.failure {
            errorMessage = error.localizedDescription
        } else {
            dismiss()
        }
    }

    private func close() {
        shortcutService.cancelRecording()
        dismiss()
    }
}
