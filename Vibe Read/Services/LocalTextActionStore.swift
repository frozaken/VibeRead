import Foundation
import Combine

struct LocalTextAction: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var prompt: String

    init(id: UUID = UUID(), name: String, prompt: String) {
        self.id = id
        self.name = name
        self.prompt = prompt
    }
}

enum BuiltInPaletteAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case readAloud
    case saveToLibrary
    case summarize
    case copy

    var id: String { rawValue }

    var name: String {
        switch self {
        case .readAloud: return "Read aloud"
        case .saveToLibrary: return "Save to Library"
        case .summarize: return "Summarize"
        case .copy: return "Copy"
        }
    }

    var icon: String {
        switch self {
        case .readAloud: return "speaker.wave.2.fill"
        case .saveToLibrary: return "bookmark"
        case .summarize: return "text.badge.star"
        case .copy: return "doc.on.doc"
        }
    }
}

/// User-editable commands shown by the action palette. Configuration is a
/// small local JSON value in UserDefaults; selected text is never persisted.
@MainActor
final class LocalTextActionStore: ObservableObject {
    static let shared = LocalTextActionStore()

    private let defaults: UserDefaults
    private let defaultsKey = "localTextActions.v1"
    private let builtInsKey = "localTextActions.builtIns.v1"

    @Published private(set) var actions: [LocalTextAction] {
        didSet { persist() }
    }
    @Published private(set) var enabledBuiltIns: Set<BuiltInPaletteAction> {
        didSet { persistBuiltIns() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([LocalTextAction].self, from: data) {
            let sanitized = Self.sanitized(decoded)
            actions = sanitized

            // Older builds appended a placeholder immediately whenever Add
            // Action was clicked. Collapse exact duplicates once on load so
            // those accidental rows disappear without disturbing user order.
            if sanitized != decoded,
               let repairedData = try? JSONEncoder().encode(sanitized) {
                defaults.set(repairedData, forKey: defaultsKey)
            }
        } else {
            actions = Self.defaultActions
        }
        if let values = defaults.array(forKey: builtInsKey) as? [String] {
            enabledBuiltIns = Set(values.compactMap(BuiltInPaletteAction.init(rawValue:)))
        } else {
            enabledBuiltIns = Set(BuiltInPaletteAction.allCases)
        }
    }

    /// Returns an inline validation message suitable for the action editor.
    func validationMessage(
        name: String,
        prompt: String,
        excluding actionID: UUID? = nil
    ) -> String? {
        let name = Self.trimmed(name)
        let prompt = Self.trimmed(prompt)

        if name.isEmpty { return "Enter an action name." }
        if prompt.isEmpty { return "Enter the instruction this action should follow." }

        let duplicateExists = actions.contains { action in
            action.id != actionID
                && Self.trimmed(action.name) == name
                && Self.trimmed(action.prompt) == prompt
        }
        if duplicateExists { return "An identical action already exists." }
        return nil
    }

    /// Creates or updates an action without changing its position in the list.
    @discardableResult
    func save(id: UUID?, name: String, prompt: String) -> Bool {
        guard validationMessage(name: name, prompt: prompt, excluding: id) == nil else {
            return false
        }

        let normalizedName = Self.trimmed(name)
        let normalizedPrompt = Self.trimmed(prompt)

        if let id {
            guard let index = actions.firstIndex(where: { $0.id == id }) else {
                return false
            }
            actions[index] = LocalTextAction(
                id: id,
                name: normalizedName,
                prompt: normalizedPrompt
            )
        } else {
            actions.append(LocalTextAction(name: normalizedName, prompt: normalizedPrompt))
        }
        return true
    }

    func remove(id: UUID) {
        actions.removeAll { $0.id == id }
    }

    func reset() {
        actions = Self.defaultActions
        enabledBuiltIns = Set(BuiltInPaletteAction.allCases)
    }

    func isEnabled(_ action: BuiltInPaletteAction) -> Bool {
        enabledBuiltIns.contains(action)
    }

    func setEnabled(_ isEnabled: Bool, for action: BuiltInPaletteAction) {
        if isEnabled { enabledBuiltIns.insert(action) }
        else { enabledBuiltIns.remove(action) }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(actions) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    private func persistBuiltIns() {
        defaults.set(enabledBuiltIns.map(\.rawValue).sorted(), forKey: builtInsKey)
    }

    private static func sanitized(_ source: [LocalTextAction]) -> [LocalTextAction] {
        var seen = Set<ActionIdentity>()
        var result: [LocalTextAction] = []

        for action in source {
            let name = trimmed(action.name)
            let prompt = trimmed(action.prompt)
            guard !name.isEmpty, !prompt.isEmpty else { continue }

            let identity = ActionIdentity(name: name, prompt: prompt)
            guard seen.insert(identity).inserted else { continue }

            result.append(LocalTextAction(id: action.id, name: name, prompt: prompt))
        }
        return result
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct ActionIdentity: Hashable {
        let name: String
        let prompt: String
    }

    static let defaultActions = [
        LocalTextAction(
            name: "Fix spelling & grammar",
            prompt: "Fix spelling, grammar, and punctuation while preserving the writer's voice. Return only the corrected text."
        ),
        LocalTextAction(
            name: "Make concise",
            prompt: "Make this text concise without losing important meaning. Return only the revised text."
        ),
        LocalTextAction(
            name: "Professional tone",
            prompt: "Rewrite this in a warm, professional tone. Return only the rewritten text."
        ),
        LocalTextAction(
            name: "Turn into bullets",
            prompt: "Turn this into a clear, compact bullet list. Return only the bullet list."
        )
    ]
}
