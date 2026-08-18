import Foundation
import Security

enum KeychainError: LocalizedError {
    case couldNotEncodeSecret
    case couldNotVerifySecret
    case operationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .couldNotEncodeSecret:
            return "The API key could not be encoded for Keychain storage."
        case .couldNotVerifySecret:
            return "The API key could not be verified after saving it to macOS Keychain."
        case .operationFailed(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String?
            return detail.map { "macOS Keychain: \($0)" }
                ?? "macOS Keychain failed with status \(status)."
        }
    }
}

final class KeychainHelper {
    static let shared = KeychainHelper()

    /// Namespace secrets by the installed app rather than a hosted-service
    /// identifier, so independently built forks do not share Keychain items.
    private var service: String {
        "\(Bundle.main.bundleIdentifier ?? "VibeRead").local-secrets"
    }

    private init() {}

    func save(token: String, for key: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw KeychainError.couldNotEncodeSecret
        }

        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let updateStatus = SecItemUpdate(
            lookup as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.operationFailed(updateStatus)
        }

        var insertion = lookup
        insertion[kSecValueData as String] = data
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.operationFailed(addStatus)
        }
    }

    func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.operationFailed(status)
        }
    }
}
