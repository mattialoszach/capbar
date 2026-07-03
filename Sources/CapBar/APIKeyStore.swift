import Foundation
import Security

// Stores admin API keys in a user-only file, like the provider CLIs do with
// their own credentials. CapBar is not signed with a stable identity, so a
// Keychain item would trigger an access prompt after every rebuild.
enum APIKeyStore {
    static let defaultFileURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CapBar/api-keys.json")

    static func key(for provider: ProviderID, fileURL: URL = defaultFileURL) -> String? {
        migrateLegacyKeychainIfNeeded(fileURL: fileURL)

        guard let key = readAll(fileURL: fileURL)[provider.rawValue]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            key.isEmpty == false else {
            return nil
        }
        return key
    }

    static func hasKey(for provider: ProviderID, fileURL: URL = defaultFileURL) -> Bool {
        key(for: provider, fileURL: fileURL) != nil
    }

    @discardableResult
    static func setKey(_ key: String, for provider: ProviderID, fileURL: URL = defaultFileURL) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }

        var keys = readAll(fileURL: fileURL)
        keys[provider.rawValue] = trimmed
        return writeAll(keys, fileURL: fileURL)
    }

    static func deleteKey(for provider: ProviderID, fileURL: URL = defaultFileURL) {
        var keys = readAll(fileURL: fileURL)
        guard keys.removeValue(forKey: provider.rawValue) != nil else { return }
        _ = writeAll(keys, fileURL: fileURL)
    }

    private static func readAll(fileURL: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let keys = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return keys
    }

    private static func writeAll(_ keys: [String: String], fileURL: URL) -> Bool {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(keys)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
            return true
        } catch {
            return false
        }
    }

    // MARK: - Legacy Keychain migration

    private static let legacyKeychainService = "CapBar API Admin Keys"
    private static let migrationFlagKey = "CapBar.APIKeyStore.KeychainMigrationAttempted"

    private static func migrateLegacyKeychainIfNeeded(fileURL: URL) {
        guard fileURL == defaultFileURL else { return }

        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: migrationFlagKey) == false else { return }
        defaults.set(true, forKey: migrationFlagKey)

        var keys = readAll(fileURL: fileURL)
        var migratedProviders: [ProviderID] = []
        for provider in ProviderID.allCases where keys[provider.rawValue] == nil {
            guard let legacyKey = readLegacyKeychainKey(for: provider) else { continue }
            keys[provider.rawValue] = legacyKey
            migratedProviders.append(provider)
        }

        guard migratedProviders.isEmpty == false, writeAll(keys, fileURL: fileURL) else { return }
        for provider in migratedProviders {
            deleteLegacyKeychainKey(for: provider)
        }
    }

    private static func readLegacyKeychainKey(for provider: ProviderID) -> String? {
        var query = legacyKeychainQuery(for: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              key.isEmpty == false else {
            return nil
        }
        return key
    }

    private static func deleteLegacyKeychainKey(for provider: ProviderID) {
        SecItemDelete(legacyKeychainQuery(for: provider) as CFDictionary)
    }

    private static func legacyKeychainQuery(for provider: ProviderID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyKeychainService,
            kSecAttrAccount as String: "\(provider.rawValue)-admin-key"
        ]
    }
}
