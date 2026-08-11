//
//  SnapshotStore.swift
//  notchboard
//
//  Periodic encrypted snapshots of every collection, kept in ~/.notchboard/snapshots
//  (vision.md §14.5.2 — the dot-folder is the deliberate dev-tool idiom, like ~/.claude).
//  This is the recovery path for catalogue-level accidents on *this* Mac: a botched
//  import, a mass delete, a future sync gone wrong. Cross-machine recovery stays the
//  export's job, because the sealing key below never leaves this machine.
//
//  Snapshots carry real secret values, so they are never written in the clear: each file
//  is one AES-GCM box sealed under a random device-local key held in the Keychain — under
//  its own service, out of reach of the secrets store's pruneOrphans sweep. That makes the
//  folder safe to include in any backup.
//

import CryptoKit
import Foundation
import Security
import os

/// What a snapshot file holds once decrypted.
struct SnapshotPayload: Codable {
    /// Stays 1 pre-release like every other stamp (vision.md §14.5): an old-shaped
    /// snapshot fails decode and refuses as unreadable — no version ledger needed.
    static let currentVersion = 1
    var formatVersion: Int
    var savedAt: Date
    var collections: [NBCollection]
    var activeCollectionID: String

    init(collections: [NBCollection], activeCollectionID: String, savedAt: Date = Date()) {
        self.formatVersion = Self.currentVersion
        self.savedAt = savedAt
        self.collections = collections
        self.activeCollectionID = activeCollectionID
    }
}

enum SnapshotStore {
    private static let logger = Logger(subsystem: "flourix.notchboard", category: "snapshots")

    /// Bounded rotation: enough history to reach back a working day or two, small enough
    /// to never matter on disk. Exact numbers are an open question (vision.md §14.7).
    static let maxSnapshots = 24
    /// Minimum spacing between snapshots. save() calls this on every debounced persist;
    /// the gate is what turns "on every change" into "periodic".
    static let minInterval: TimeInterval = 15 * 60

    /// Test seam — the suite points this at a scratch directory so tests never touch the
    /// real ~/.notchboard.
    static var directoryURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".notchboard/snapshots", isDirectory: true)

    // The sealing key lives under its own Keychain service: SecretsStore.pruneOrphans
    // enumerates and deletes within *its* service, and this key must never be collateral.
    private static let keyService = "flourix.notchboard.device"
    private static let keyAccount = "snapshot-key"

    enum SnapshotError: Error, Equatable {
        case keyUnavailable
        case unreadable
        case unsupportedVersion(Int)
    }

    /// Exact-match version check, same rule as WorkspaceTransfer: pre-release there is one
    /// format, and a snapshot from any other build version is refused rather than
    /// tolerated (vision.md §14.5). Internal so tests can hit it without the device key.
    static func validatePayloadVersion(_ payload: SnapshotPayload) throws {
        guard payload.formatVersion == SnapshotPayload.currentVersion else {
            throw SnapshotError.unsupportedVersion(payload.formatVersion)
        }
    }

    /// Writes a snapshot unless the newest one is younger than `minInterval`. Best-effort
    /// like AppStateStore.save — a failed snapshot logs, it never interrupts the app.
    /// `at` exists for tests: filenames carry second granularity, so exercising rotation
    /// needs distinct timestamps without sleeping.
    static func recordIfDue(collections: [NBCollection], activeCollectionID: String, force: Bool = false, at date: Date = Date()) {
        if !force, let newest = list().first,
           let modified = try? newest.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           Date().timeIntervalSince(modified) < minInterval {
            return
        }
        guard let key = deviceKey() else {
            logger.error("snapshot skipped: device key unavailable")
            return
        }
        do {
            let payload = SnapshotPayload(collections: collections, activeCollectionID: activeCollectionID, savedAt: date)
            let plaintext = try JSONEncoder().encode(payload)
            let box = try AES.GCM.seal(plaintext, using: key)
            guard let combined = box.combined else { return }

            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let stamp = Self.filenameFormatter.string(from: payload.savedAt)
            let url = directoryURL.appendingPathComponent("notchboard-\(stamp).nbsnap")
            try combined.write(to: url, options: .atomic)
            rotate()
        } catch {
            logger.error("snapshot write failed: \(error)")
        }
    }

    /// Snapshot files, newest first.
    static func list() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return contents
            .filter { $0.pathExtension == "nbsnap" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func load(from url: URL) throws -> SnapshotPayload {
        guard let key = deviceKey() else { throw SnapshotError.keyUnavailable }
        guard let combined = try? Data(contentsOf: url),
              let box = try? AES.GCM.SealedBox(combined: combined),
              let plaintext = try? AES.GCM.open(box, using: key),
              let payload = try? JSONDecoder().decode(SnapshotPayload.self, from: plaintext) else {
            throw SnapshotError.unreadable
        }
        try validatePayloadVersion(payload)
        return payload
    }

    private static func rotate() {
        let stale = list().dropFirst(maxSnapshots)
        for url in stale {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Timestamped names sort lexically = chronologically, which `list()` relies on.
    private static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    // MARK: - Device key

    /// Loads the sealing key, creating it on first use. Returns nil only when the Keychain
    /// refuses both read and write (locked/denied) — snapshots pause rather than falling
    /// back to writing plaintext.
    ///
    /// Stands in for the Keychain key in tests, the same seam `directoryURL` already provides for
    /// the snapshot folder. Reading the real item is not merely untidy in a test, it can block
    /// forever: a generic-password ACL is bound to the binary that created it, the app is ad-hoc
    /// signed so a clone builds with no Apple account, and every rebuild is therefore a new code
    /// identity that securityd asks the user to approve. A headless run can never answer that
    /// modal, so the whole suite deadlocked on the main actor inside `SecItemCopyMatching`.
    static var deviceKeyOverride: SymmetricKey?

    private static func deviceKey() -> SymmetricKey? {
        if let deviceKeyOverride { return deviceKeyOverride }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: keyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else {
            logger.error("snapshot key read failed: \(status)")
            return nil
        }

        var bytes = Data(count: 32)
        let randomStatus = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        guard randomStatus == errSecSuccess else { return nil }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: keyAccount,
            kSecValueData as String: bytes,
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            logger.error("snapshot key create failed: \(addStatus)")
            return nil
        }
        return SymmetricKey(data: bytes)
    }
}
