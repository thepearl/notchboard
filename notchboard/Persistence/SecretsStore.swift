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

import Foundation
import Security
import os

enum SecretsStore {
    private static let service = "flourix.notchboard.secrets"
    private static let logger = Logger(subsystem: "flourix.notchboard", category: "secrets")

    static func save(_ value: String, for key: String) {
        let data = Data(value.utf8)
        var query = baseQuery(for: key)

        let update = [kSecValueData as String: data] as CFDictionary
        let updateStatus = SecItemUpdate(query as CFDictionary, update)
        if updateStatus == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            if addStatus != errSecSuccess {
                logger.error("keychain add failed for \(key, privacy: .public): \(addStatus)")
            }
        } else if updateStatus != errSecSuccess {
            logger.error("keychain update failed for \(key, privacy: .public): \(updateStatus)")
        }
    }

    static func load(for key: String) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                logger.error("keychain read failed for \(key, privacy: .public): \(status)")
            }
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func delete(for key: String) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    private static func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
