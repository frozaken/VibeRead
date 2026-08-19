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

    private let defaultsKey = "localTextActions.v1"
    private let builtInsKey = "localTextActions.builtIns.v1"

    @Published var actions: [LocalTextAction] {
        didSet { persist() }
    }
    @Published var enabledBuiltIns: Set<BuiltInPaletteAction> {
        didSet { persistBuiltIns() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([LocalTextAction].self, from: data) {
            actions = decoded
        } else {
            actions = Self.defaultActions
        }
        if let values = UserDefaults.standard.array(forKey: builtInsKey) as? [String] {
            enabledBuiltIns = Set(values.compactMap(BuiltInPaletteAction.init(rawValue:)))
        } else {
            enabledBuiltIns = Set(BuiltInPaletteAction.allCases)
        }
    }

    func add(name: String = "New action", prompt: String = "Rewrite the text clearly. Return only the rewritten text.") {
        actions.append(LocalTextAction(name: name, prompt: prompt))
    }

    func remove(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where actions.indices.contains(index) {
            actions.remove(at: index)
        }
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
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func persistBuiltIns() {
        UserDefaults.standard.set(enabledBuiltIns.map(\.rawValue).sorted(), forKey: builtInsKey)
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
