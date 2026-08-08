//
//  RoomKeyStore.swift
//  notchboard
//
//  Keychain home for room secrets: the room password (derives the payload key, shared
//  like a wifi password) and the broker credential (persona 2's shared user/pass), one
//  pair per broker+room.
//
//  Its own service, deliberately: SecretsStore.pruneOrphans enumerates and deletes within
//  *its* service keyed off element ids, and a room password must never be collateral of
//  an element sweep — the same isolation the snapshot device key gets
//  (flourix.notchboard.device).
//
//  Account keys hash the broker host + room slug so the account list leaks nothing
//  readable, and so the same room on two brokers stores two passwords (they derive
//  different keys anyway — the salt binds to the host).
//

import CryptoKit
import Foundation
import Security
import os

enum RoomKeyStore {
    private static let service = "flourix.notchboard.rooms"
    private static let logger = Logger(subsystem: "flourix.notchboard", category: "sync")

    // MARK: - Room password

    /// False when the Keychain refused the write — callers must treat that as NOT stored
    /// (the SecretsStore rule: a failed write persisted as success is permanent loss).
    @discardableResult
    static func saveRoomPassword(_ password: String, for config: NBRoomConfig) -> Bool {
        guard let account = account(for: config, kind: "room") else { return false }
        return save(password, account: account)
    }

    static func roomPassword(for config: NBRoomConfig) -> String? {
        guard let account = account(for: config, kind: "room") else { return nil }
        return load(account: account)
    }

    // MARK: - Broker account credential
    //
    // Persona 2's shared broker account (§14.3 — HiveMQ Cloud, a hardened mosquitto).
    // The username travels inside the broker URL (it's shared, like the address); this
    // password never travels, exactly like the room password.

    @discardableResult
    static func saveBrokerPassword(_ password: String, for config: NBRoomConfig) -> Bool {
        guard let account = account(for: config, kind: "broker") else { return false }
        return save(password, account: account)
    }

    static func brokerPassword(for config: NBRoomConfig) -> String? {
        guard let account = account(for: config, kind: "broker") else { return nil }
        return load(account: account)
    }

    /// Leave-room and collection-delete both come through here: a password for a room
    /// this Mac no longer belongs to is pure liability.
    static func deletePasswords(for config: NBRoomConfig) {
        for kind in ["room", "broker"] {
            guard let account = account(for: config, kind: kind) else { continue }
            SecItemDelete(baseQuery(account: account) as CFDictionary)
        }
    }

    // MARK: - Plumbing

    private static func account(for config: NBRoomConfig, kind: String) -> String? {
        guard let host = config.brokerHost else { return nil }
        let digest = SHA256.hash(data: Data("\(host)/\(config.room)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + "." + kind
    }

    private static func save(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let update = SecItemUpdate(
            baseQuery(account: account) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else {
            logger.error("room keychain update failed: \(update)")
            return false
        }
        var add = baseQuery(account: account)
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("room keychain add failed: \(status)")
        }
        return status == errSecSuccess
    }

    private static func load(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
