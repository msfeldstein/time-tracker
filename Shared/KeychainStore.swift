import Foundation
import Security
import TimeTrackerCore

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
    enum Source: Equatable {
        /// Entered in Settings; stored in the Keychain. Always wins.
        case settings
        /// Built in from ANTHROPIC_API_KEY in the git-ignored Config/Local.xcconfig.
        case builtIn
        case missing
    }

    private static let account = "anthropic-api-key"
    private static let bundledInfoKey = "TTBundledAnthropicKey"

    /// The key to use: one saved in Settings, otherwise the built-in one.
    static func load() -> String? {
        savedKey() ?? bundledKey()
    }

    static var source: Source {
        if savedKey() != nil { return .settings }
        if bundledKey() != nil { return .builtIn }
        return .missing
    }

    static func savedKey() -> String? {
        guard let key = KeychainStore.string(for: account), !key.isEmpty else { return nil }
        return key
    }

    /// Read from the app's Info.plist on every call and never copied into the Keychain, so
    /// removing it from Local.xcconfig and rebuilding removes it from the phone. The widget
    /// extension's Info.plist doesn't carry it.
    static func bundledKey() -> String? {
        BundledAPIKey.sanitize(Bundle.main.object(forInfoDictionaryKey: bundledInfoKey) as? String)
    }

    static func save(_ key: String) throws {
        try KeychainStore.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: account)
    }

    /// Removes the key saved in Settings. A built-in key, if any, takes over again.
    static func remove() {
        KeychainStore.delete(account)
    }
}
