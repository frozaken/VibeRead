import Foundation

enum EnvironmentKeyImporterError: LocalizedError, Equatable {
    case unreadable
    case missingVariable(String)
    case invalidValue(String)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "Vibe Read could not read that .env file."
        case .missingVariable(let name):
            return "That file does not contain \(name)."
        case .invalidValue(let name):
            return "\(name) is empty or uses an unsupported multiline value."
        }
    }
}

enum EnvironmentKeyImporter {
    static func value(named name: String, in fileURL: URL) throws -> String {
        let contents: String
        do {
            contents = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw EnvironmentKeyImporterError.unreadable
        }
        guard let value = value(named: name, in: contents) else {
            throw EnvironmentKeyImporterError.missingVariable(name)
        }
        guard !value.isEmpty, !value.contains("\n"), !value.contains("\r") else {
            throw EnvironmentKeyImporterError.invalidValue(name)
        }
        return value
    }

    static func value(named name: String, in contents: String) -> String? {
        for rawLine in contents.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") {
                line.removeFirst("export ".count)
            }
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard key == name else { continue }
            var value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               let first = value.first,
               let last = value.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                value.removeFirst()
                value.removeLast()
            }
            return value
        }
        return nil
    }
}
