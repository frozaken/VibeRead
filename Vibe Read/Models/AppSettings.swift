import Foundation
import Combine
import AppKit

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    @Published var themeMode: ThemeMode {
        didSet { defaults.set(themeMode.rawValue, forKey: "themeMode") }
    }
    @Published var preferredVoiceId: String {
        didSet { defaults.set(preferredVoiceId, forKey: "preferredVoiceId") }
    }
    @Published var readAloudProvider: ReadAloudProvider {
        didSet { defaults.set(readAloudProvider.rawValue, forKey: "readAloudProvider") }
    }
    @Published var elevenLabsVoiceId: String {
        didSet { defaults.set(elevenLabsVoiceId, forKey: "elevenLabsVoiceId") }
    }
    @Published var elevenLabsVoiceName: String {
        didSet { defaults.set(elevenLabsVoiceName, forKey: "elevenLabsVoiceName") }
    }
    @Published var elevenLabsTTSModel: String {
        didSet { defaults.set(elevenLabsTTSModel, forKey: "elevenLabsTTSModel") }
    }
    @Published var voiceStability: Double {
        didSet { defaults.set(voiceStability, forKey: "voiceStability") }
    }
    @Published var voiceSimilarityBoost: Double {
        didSet { defaults.set(voiceSimilarityBoost, forKey: "voiceSimilarityBoost") }
    }
    @Published var voiceStyle: Double {
        didSet { defaults.set(voiceStyle, forKey: "voiceStyle") }
    }
    @Published var voiceSpeakerBoost: Bool {
        didSet { defaults.set(voiceSpeakerBoost, forKey: "voiceSpeakerBoost") }
    }
    @Published var voiceSpeed: Double {
        didSet { defaults.set(voiceSpeed, forKey: "voiceSpeed") }
    }
    @Published var speedBoostMultiplier: Double {
        didSet { defaults.set(speedBoostMultiplier, forKey: "speedBoostMultiplier") }
    }
    @Published var customVocabulary: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(customVocabulary) {
                defaults.set(data, forKey: "customVocabulary")
            }
        }
    }
    @Published var dictationHotkeyEnabled: Bool {
        didSet { defaults.set(dictationHotkeyEnabled, forKey: "dictationHotkeyEnabled") }
    }
    @Published var autoPasteAfterDictation: Bool {
        didSet { defaults.set(autoPasteAfterDictation, forKey: "autoPasteAfterDictation") }
    }
    @Published var dictationSoundEffectsEnabled: Bool {
        didSet { defaults.set(dictationSoundEffectsEnabled, forKey: "dictationSoundEffectsEnabled") }
    }
    @Published var selectedMicrophoneId: String {
        didSet { defaults.set(selectedMicrophoneId, forKey: "selectedMicrophoneId") }
    }
    @Published var dictationModes: [DictationMode] {
        didSet {
            if let data = try? JSONEncoder().encode(dictationModes) {
                defaults.set(data, forKey: "dictationModes")
            }
        }
    }
    @Published var activeDictationModeId: String {
        didSet { defaults.set(activeDictationModeId, forKey: "activeDictationModeId") }
    }
    @Published var shortcuts: [CustomKeyboardShortcut] {
        didSet {
            if let data = try? JSONEncoder().encode(shortcuts) {
                defaults.set(data, forKey: "keyboardShortcuts")
            }
            NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
        }
    }

    var activeDictationMode: DictationMode {
        dictationModes.first(where: { $0.id == activeDictationModeId }) ?? .plain
    }

    private init() {
        themeMode = ThemeMode(rawValue: defaults.string(forKey: "themeMode") ?? "system") ?? .system
        let oldVoiceID = defaults.string(forKey: "preferredVoiceId") ?? ""
        preferredVoiceId = oldVoiceID.contains(".") ? oldVoiceID : ""
        let migratedElevenLabsVoiceID = defaults.string(forKey: "elevenLabsVoiceId")
            ?? (oldVoiceID.contains(".") ? "21m00Tcm4TlvDq8ikWAM" : oldVoiceID)
        elevenLabsVoiceId = migratedElevenLabsVoiceID.isEmpty
            ? "21m00Tcm4TlvDq8ikWAM"
            : migratedElevenLabsVoiceID
        elevenLabsVoiceName = defaults.string(forKey: "elevenLabsVoiceName") ?? "Rachel"
        elevenLabsTTSModel = defaults.string(forKey: "elevenLabsTTSModel")
            ?? "eleven_multilingual_v2"
        voiceStability = defaults.object(forKey: "voiceStability") as? Double ?? 0.5
        voiceSimilarityBoost = defaults.object(forKey: "voiceSimilarityBoost") as? Double ?? 0.75
        voiceStyle = defaults.object(forKey: "voiceStyle") as? Double ?? 0
        voiceSpeakerBoost = defaults.object(forKey: "voiceSpeakerBoost") as? Bool ?? true
        let hasConfiguredElevenLabs = defaults.bool(
            forKey: "provider.v2.credential.elevenLabs.configured"
        )
        readAloudProvider = ReadAloudProvider(
            rawValue: defaults.string(forKey: "readAloudProvider") ?? ""
        ) ?? (hasConfiguredElevenLabs ? .elevenLabs : .macOS)
        voiceSpeed = defaults.object(forKey: "voiceSpeed") as? Double ?? 1
        speedBoostMultiplier = defaults.object(forKey: "speedBoostMultiplier") as? Double ?? 1.5
        dictationHotkeyEnabled = defaults.object(forKey: "dictationHotkeyEnabled") as? Bool ?? true
        autoPasteAfterDictation = defaults.object(forKey: "autoPasteAfterDictation") as? Bool ?? true
        dictationSoundEffectsEnabled = defaults.object(forKey: "dictationSoundEffectsEnabled") as? Bool ?? true
        selectedMicrophoneId = defaults.string(forKey: "selectedMicrophoneId") ?? "builtin"

        if let data = defaults.data(forKey: "customVocabulary"),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            customVocabulary = decoded
        } else {
            customVocabulary = []
        }

        if let data = defaults.data(forKey: "dictationModes"),
           let decoded = try? JSONDecoder().decode([DictationMode].self, from: data),
           !decoded.isEmpty {
            dictationModes = decoded
        } else {
            dictationModes = DictationMode.defaultModes
        }
        activeDictationModeId = defaults.string(forKey: "activeDictationModeId") ?? DictationMode.plain.id

        var loaded: [CustomKeyboardShortcut]
        if let data = defaults.data(forKey: "keyboardShortcuts"),
           let decoded = try? JSONDecoder().decode([CustomKeyboardShortcut].self, from: data) {
            loaded = decoded
        } else {
            loaded = []
        }
        // Preserve user customizations while adding newly introduced actions.
        for fallback in Self.defaultShortcuts where !loaded.contains(where: { $0.action == fallback.action }) {
            loaded.append(fallback)
        }
        shortcuts = loaded
    }

    func shortcuts(for action: ShortcutAction) -> [CustomKeyboardShortcut] {
        shortcuts.filter { $0.action == action }
    }

    func primaryShortcut(for action: ShortcutAction) -> CustomKeyboardShortcut? {
        shortcuts.first { $0.action == action }
    }

    func addShortcut(_ shortcut: CustomKeyboardShortcut) -> Result<Void, ShortcutError> {
        if let error = CustomKeyboardShortcut.validate(keys: shortcut.keys).failure { return .failure(error) }
        if let existing = shortcuts.first(where: { Set($0.keys) == Set(shortcut.keys) }) {
            return .failure(.alreadyInUse(existing.action))
        }
        shortcuts.append(shortcut)
        return .success(())
    }

    func updateShortcut(_ shortcut: CustomKeyboardShortcut) -> Result<Void, ShortcutError> {
        if let error = CustomKeyboardShortcut.validate(keys: shortcut.keys).failure { return .failure(error) }
        if let existing = shortcuts.first(where: { Set($0.keys) == Set(shortcut.keys) && $0.id != shortcut.id }) {
            return .failure(.alreadyInUse(existing.action))
        }
        guard let index = shortcuts.firstIndex(where: { $0.id == shortcut.id }) else { return .success(()) }
        shortcuts[index] = shortcut
        return .success(())
    }

    func resetShortcutsToDefault() {
        shortcuts = Self.defaultShortcuts
    }

    static var defaultShortcuts: [CustomKeyboardShortcut] {
        [
            .init(keys: [.fn], action: .handsFree),
            .init(keys: [.fn, .space], action: .pushToTalk),
            .init(keys: [.fn, .control], action: .commandMode),
            .init(keys: [.control, .command, .v], action: .pasteLastTranscript),
            .init(keys: [.command, .e], action: .openActionPalette),
            .init(keys: [.command, .shift, .e], action: .readSelection),
            .init(keys: [.command, .shift, .space], action: .toggleReadAloud)
        ]
    }
}

enum ReadAloudProvider: String, CaseIterable, Codable, Identifiable {
    case elevenLabs
    case macOS

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .elevenLabs: return "ElevenLabs"
        case .macOS: return "macOS"
        }
    }
}

enum ThemeMode: String, CaseIterable, Codable {
    case system, dark, light
}

enum ShortcutAction: String, CaseIterable, Codable, Identifiable {
    case pushToTalk = "push_to_talk"
    case handsFree = "hands_free"
    case commandMode = "command_mode"
    case pasteLastTranscript = "paste_transcript"
    case openActionPalette = "open_action_palette"
    case readSelection = "read_selection"
    case toggleReadAloud = "toggle_read_aloud"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pushToTalk: return "Push to talk"
        case .handsFree: return "Hands-free dictation"
        case .commandMode: return "Voice action palette"
        case .pasteLastTranscript: return "Paste last dictation"
        case .openActionPalette: return "Open action palette"
        case .readSelection: return "Read selected text"
        case .toggleReadAloud: return "Pause or resume reading"
        }
    }

    var description: String {
        switch self {
        case .pushToTalk: return "Hold to record, release to transcribe"
        case .handsFree: return "Press once to start and once to finish"
        case .commandMode: return "Dictate text, then choose a local action"
        case .pasteLastTranscript: return "Paste the last saved dictation"
        case .openActionPalette: return "Show editable actions for selected text"
        case .readSelection: return "Read selected text with a macOS voice"
        case .toggleReadAloud: return "Pause or resume local read-aloud"
        }
    }
}

enum KeyCode: String, CaseIterable, Codable, Equatable, Hashable {
    case fn = "fn"
    case control = "⌃ Ctrl"
    case option = "⌥ Opt"
    case command = "⌘ Cmd"
    case shift = "⇧ Shift"
    case space = "Space"
    case `return` = "Return"
    case tab = "Tab"
    case escape = "Esc"
    case delete = "Delete"
    case a = "A", b = "B", c = "C", d = "D", e = "E", f = "F"
    case g = "G", h = "H", i = "I", j = "J", k = "K", l = "L"
    case m = "M", n = "N", o = "O", p = "P", q = "Q", r = "R"
    case s = "S", t = "T", u = "U", v = "V", w = "W", x = "X", y = "Y", z = "Z"
    case zero = "0", one = "1", two = "2", three = "3", four = "4"
    case five = "5", six = "6", seven = "7", eight = "8", nine = "9"
    case f1 = "F1", f2 = "F2", f3 = "F3", f4 = "F4", f5 = "F5", f6 = "F6"
    case f7 = "F7", f8 = "F8", f9 = "F9", f10 = "F10", f11 = "F11", f12 = "F12"

    var displayName: String { self == .fn ? "🌐 fn" : rawValue }

    var cgKeyCode: UInt16? {
        switch self {
        case .space: return 49; case .return: return 36; case .tab: return 48; case .escape: return 53; case .delete: return 51
        case .a: return 0; case .b: return 11; case .c: return 8; case .d: return 2; case .e: return 14
        case .f: return 3; case .g: return 5; case .h: return 4; case .i: return 34; case .j: return 38
        case .k: return 40; case .l: return 37; case .m: return 46; case .n: return 45; case .o: return 31
        case .p: return 35; case .q: return 12; case .r: return 15; case .s: return 1; case .t: return 17
        case .u: return 32; case .v: return 9; case .w: return 13; case .x: return 7; case .y: return 16; case .z: return 6
        case .zero: return 29; case .one: return 18; case .two: return 19; case .three: return 20; case .four: return 21
        case .five: return 23; case .six: return 22; case .seven: return 26; case .eight: return 28; case .nine: return 25
        case .f1: return 122; case .f2: return 120; case .f3: return 99; case .f4: return 118; case .f5: return 96
        case .f6: return 97; case .f7: return 98; case .f8: return 100; case .f9: return 101; case .f10: return 109
        case .f11: return 103; case .f12: return 111
        default: return nil
        }
    }

    static func from(keyCode: UInt16) -> KeyCode? {
        allCases.first { $0.cgKeyCode == keyCode }
    }
}

struct CustomKeyboardShortcut: Identifiable, Codable, Equatable {
    let id: UUID
    var keys: [KeyCode]
    var action: ShortcutAction

    init(id: UUID = UUID(), keys: [KeyCode], action: ShortcutAction) {
        self.id = id
        self.keys = keys
        self.action = action
    }

    var displayString: String { keys.map(\.displayName).joined(separator: " + ") }
    static let maxKeys = 3

    static func validate(keys: [KeyCode]) -> Result<Void, ShortcutError> {
        if keys.isEmpty { return .failure(.empty) }
        if keys.count > maxKeys { return .failure(.tooManyKeys) }
        return .success(())
    }
}

enum ShortcutError: LocalizedError {
    case empty
    case tooManyKeys
    case alreadyInUse(ShortcutAction)

    var errorDescription: String? {
        switch self {
        case .empty: return "Shortcut cannot be empty"
        case .tooManyKeys: return "A shortcut can use at most three keys"
        case .alreadyInUse(let action): return "That shortcut is already used by \(action.displayName)"
        }
    }
}

struct DictationMode: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var systemPrompt: String
    var isBuiltIn: Bool

    var hasCustomPrompt: Bool { !systemPrompt.isEmpty }
    static let plain = DictationMode(id: "default", name: "Default", systemPrompt: "", isBuiltIn: true)
    static let defaultModes = [plain]
}

extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

extension Notification.Name {
    static let shortcutsDidChange = Notification.Name("shortcutsDidChange")
}
