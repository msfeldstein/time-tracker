import Foundation
import Security

/// Minimal generic-password Keychain wrapper. Items stay on this device only and are not synced.
enum KeychainStore {
    private static let service = "TimeTracker"

    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
    }

    static func string(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, for account: String) throws {
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(base as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            let addStatus = SecItemAdd(base.merging(update) { $1 } as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum AnthropicKey {
    private static let account = "anthropic-api-key"

    static func load() -> String? {
        guard let key = KeychainStore.string(for: account), !key.isEmpty else { return nil }
        return key
    }

    static func save(_ key: String) throws {
        try KeychainStore.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: account)
    }

    static func remove() {
        KeychainStore.delete(account)
    }
}
