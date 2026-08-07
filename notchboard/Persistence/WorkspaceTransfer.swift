//
//  WorkspaceTransfer.swift
//  notchboard
//
//  Export/import a collection as a portable JSON file — the invitation, bootstrap and
//  backup of vision.md §14, never the sync channel. Two rules define the format:
//
//  - Secrets always travel, always encrypted (§14.5.1). There is exactly one export mode:
//    a mandatory password seals every secret value into an AES-GCM envelope, so a file in
//    Slack/email/Drive never carries credentials in the clear and a second Mac never means
//    retyping them. The in-band copies inside the workspace JSON are blanked on export and
//    force-blanked again on import, whatever the file claims — real values only ever enter
//    through the envelope, which a hand-crafted file can't forge without the password.
//  - Claims never travel. A claim is a status light, not a document; frozen into a file it
//    arrives stale by construction (the tom/sara/mia bug, delivered by attachment).
//
//  There is exactly one format version, checked exactly: pre-release, files with any other
//  version are refused rather than tolerated (no compat code before 1.0 — vision.md §14.5).
//

import Foundation

struct WorkspaceTransferFile: Codable {
    /// A stamp for the future — version history starts at the first public release, so
    /// this stays 1 through every pre-release shape change: an old-shaped file fails
    /// decode and reads as unreadable, which is the same refusal with no v1/v2 ledger
    /// (vision.md §14.5).
    static let currentVersion = 1
    var formatVersion: Int
    var workspace: NBWorkspace
    /// Present whenever the source had secret values; nil in exports of catalogues that
    /// hold none.
    var secrets: SecretsEnvelope?
    /// The team room this collection syncs through, when it has one. The address is the
    /// invitation (§14.3: import → "join as <name>?"); the room password never travels in
    /// a file — it is shared out of band, like a wifi password.
    var room: NBRoomConfig?

    init(workspace: NBWorkspace, secrets: SecretsEnvelope? = nil, room: NBRoomConfig? = nil) {
        self.formatVersion = Self.currentVersion
        self.workspace = workspace
        self.secrets = secrets
        self.room = room
    }
}

enum WorkspaceTransfer {
    enum ImportError: Error, Equatable {
        case unreadable
        case emptyWorkspace
        case unsupportedVersion(Int)
        case wrongPassword
    }

    /// Encodes the workspace for sharing, sealing every secret value under `password`.
    /// `rounds` exists for tests — the deliberate slowness of the real KDF cost would
    /// otherwise dominate the suite.
    static func exportData(_ workspace: NBWorkspace, password: String, room: NBRoomConfig? = nil, rounds: Int = TransferCrypto.defaultRounds) throws -> Data {
        var secretValues: [String: String] = [:]
        let stripped = workspace.clearingClaims().mappingSecretValues { elementID, fieldKey, value in
            if !value.isEmpty { secretValues["\(elementID).\(fieldKey)"] = value }
            return ""
        }
        // The room address travels, its firstSyncCompleted flag doesn't — that flag
        // describes *this Mac's* relationship with the room, and an importer must start
        // from "never merged" so their first connect adopts the room's state.
        var shareableRoom = room
        shareableRoom?.firstSyncCompleted = false
        var file = WorkspaceTransferFile(workspace: stripped, room: shareableRoom)
        if !secretValues.isEmpty {
            file.secrets = try TransferCrypto.seal(secretValues, password: password, rounds: rounds)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    /// First import stage: parse, verify the version, and sanitise. The returned file's
    /// workspace is already safe to adopt — claims stripped, group order reconciled, and
    /// every in-band secret value force-blanked regardless of what the file contained.
    static func readFile(from data: Data) throws -> WorkspaceTransferFile {
        guard var file = try? JSONDecoder().decode(WorkspaceTransferFile.self, from: data) else {
            throw ImportError.unreadable
        }
        guard file.formatVersion == WorkspaceTransferFile.currentVersion else {
            throw ImportError.unsupportedVersion(file.formatVersion)
        }
        guard !file.workspace.groups.isEmpty else { throw ImportError.emptyWorkspace }
        file.workspace = file.workspace.clearingClaims().mappingSecretValues { _, _, _ in "" }
        file.workspace.reconcileGroupOrder()
        return file
    }

    /// Second import stage: open the envelope and inject its values. Only keys matching an
    /// actual secret-typed field land (the traversal is schema-driven), so the envelope
    /// can't smuggle values into non-secret fields either. A file without an envelope
    /// passes through unchanged — that's the secretless-export path and the skip path.
    static func unlockingSecrets(of file: WorkspaceTransferFile, password: String) throws -> NBWorkspace {
        guard let envelope = file.secrets else { return file.workspace }
        let values: [String: String]
        do {
            values = try TransferCrypto.open(envelope, password: password)
        } catch TransferCrypto.CryptoError.wrongPassword {
            throw ImportError.wrongPassword
        } catch {
            throw ImportError.unreadable
        }
        return file.workspace.mappingSecretValues { elementID, fieldKey, _ in
            values["\(elementID).\(fieldKey)"] ?? ""
        }
    }
}
