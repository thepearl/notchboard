//
//  SecretsStore.swift
//  notchboard
//
//  Keeps secret-typed field values (passwords etc.) in the user's Keychain instead of the
//  plaintext state.json (see vision.md §9 on secrets handling). Each value is one
//  generic-password item whose account key is "<elementID>.<fieldKey>", so AppStateStore
//  can strip secrets out of the JSON on save and re-inject them on load.
//
//  These are shared *test* credentials, not end-user data, but they still shouldn't sit
//  readable-at-rest in Application Support for any process running as the user.
//
//  No kSecAttrAccessible is set: on macOS the accessibility classes only apply to
//  data-protection (iOS-style) keychain items, which require kSecUseDataProtectionKeychain
//  and an application identifier this unsandboxed, entitlement-less build doesn't have.
//  What actually applies is the login keychain's default ACL — stating anything else in
//  the query would just mislead the next reader.
//

import Foundation
import Security
import os

enum SecretsStore {
    private static let service = "flourix.notchboard.secrets"
    private static let logger = Logger(subsystem: "flourix.notchboard", category: "secrets")

    enum LoadResult: Equatable {
        case found(String)
        case notFound
        case failure(OSStatus)
    }

    /// Stores a value, returning whether the write actually landed. A caller that strips
    /// the value from other storage (AppStateStore's placeholder swap) must only do so on
    /// `true` — treating a failed write as stored silently destroys the secret.
    @discardableResult
    static func save(_ value: String, for key: String) -> Bool {
        let data = Data(value.utf8)
        var query = baseQuery(for: key)

        let update = [kSecValueData as String: data] as CFDictionary
        let updateStatus = SecItemUpdate(query as CFDictionary, update)
        if updateStatus == errSecSuccess { return true }

        if updateStatus == errSecItemNotFound {
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            if addStatus == errSecSuccess { return true }
            logger.error("keychain add failed for \(key, privacy: .public): \(addStatus)")
            return false
        }

        logger.error("keychain update failed for \(key, privacy: .public): \(updateStatus)")
        return false
    }

    /// Distinguishes "no item stored" from a read error. The distinction matters: a read
    /// error resolved as "empty" would get persisted as empty on the next save, turning a
    /// transient locked-keychain state into permanent loss of the secret.
    static func load(for key: String) -> LoadResult {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return .failure(errSecInternalError) }
            return .found(String(decoding: data, as: UTF8.self))
        case errSecItemNotFound:
            return .notFound
        default:
            logger.error("keychain read failed for \(key, privacy: .public): \(status)")
            return .failure(status)
        }
    }

    static func delete(for key: String) {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("keychain delete failed for \(key, privacy: .public): \(status)")
        }
    }

    /// Every account key currently stored under Notchboard's Keychain service.
    static func allKeys() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            if status != errSecItemNotFound {
                logger.error("keychain enumeration failed: \(status)")
            }
            return []
        }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    /// Deletes entries that no current element references. Deleting state.json is the
    /// documented reset path, and before this sweep it orphaned every secret of the old
    /// workspace in the login keychain forever.
    static func pruneOrphans(keeping validKeys: Set<String>) {
        for key in allKeys() where !validKeys.contains(key) {
            delete(for: key)
        }
    }

    private static func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
