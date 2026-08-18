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

/// User-editable commands shown by the action palette. Configuration is a
/// small local JSON value in UserDefaults; selected text is never persisted.
@MainActor
final class LocalTextActionStore: ObservableObject {
    static let shared = LocalTextActionStore()

    private let defaultsKey = "localTextActions.v1"

    @Published var actions: [LocalTextAction] {
        didSet { persist() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([LocalTextAction].self, from: data) {
            actions = decoded
        } else {
            actions = Self.defaultActions
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
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(actions) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
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
