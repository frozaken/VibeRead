import Foundation
import Security

enum KeychainError: LocalizedError {
    case couldNotEncodeSecret
    case couldNotDecodeSecret
    case couldNotVerifySecret
    case operationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .couldNotEncodeSecret:
            return "The API key could not be encoded for Keychain storage."
        case .couldNotDecodeSecret:
            return "The API key stored in macOS Keychain could not be read as text."
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
    /// Version 3 intentionally does not discover or reuse keys created by old
    /// ad hoc builds. Those items can be bound to the previous executable and
    /// make macOS show a password dialog after an app replacement. Users add
    /// each key explicitly once for this installed build.
    private var service: String {
        "\(Bundle.main.bundleIdentifier ?? "VibeRead").local-provider-secrets.v3"
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

        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(lookup as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.operationFailed(updateStatus)
        }

        var insertion = lookup
        insertion[kSecValueData as String] = data
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.operationFailed(addStatus)
        }
    }

    func read(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.operationFailed(status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.couldNotDecodeSecret
        }
        return value
    }

    /// Compatibility helper for callers that can only treat an unavailable
    /// secret as missing. Launch and Settings rendering never call this.
    func get(key: String) -> String? {
        try? read(key: key)
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
