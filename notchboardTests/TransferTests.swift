//
//  TransferTests.swift
//  notchboardTests
//
//  The export format (vision.md §14.5.1): secrets always travel, always encrypted, claims
//  never travel, and any format version other than the current one is refused — no
//  pre-release compat (§14.5). Crypto tests run with a reduced PBKDF2 cost — the
//  production count exists to be slow, which is exactly wrong for CI.
//

import Foundation
import Testing
@testable import notchboard

@Suite("Transfer crypto")
struct TransferCryptoTests {

    @Test("Seal and open round-trip")
    func roundTrip() throws {
        let payload = ["el.password": "hunter2", "el2.token": "tk-99"]
        let envelope = try TransferCrypto.seal(payload, password: "pw", rounds: 1_000)
        #expect(try TransferCrypto.open(envelope, password: "pw") == payload)
    }

    @Test("A wrong password is an authenticated failure, never garbage")
    func wrongPassword() throws {
        let envelope = try TransferCrypto.seal(["k": "v"], password: "right", rounds: 1_000)
        #expect(throws: TransferCrypto.CryptoError.wrongPassword) {
            try TransferCrypto.open(envelope, password: "wrong")
        }
    }

    @Test("Tampered ciphertext fails closed")
    func tamperDetection() throws {
        var envelope = try TransferCrypto.seal(["k": "v"], password: "pw", rounds: 1_000)
        envelope.sealed[envelope.sealed.count / 2] ^= 0xFF
        #expect(throws: TransferCrypto.CryptoError.wrongPassword) {
            try TransferCrypto.open(envelope, password: "pw")
        }
    }

    @Test("An absurd KDF cost in a crafted file is refused, not obeyed")
    func absurdRoundsRefused() throws {
        // Without the cap, a hand-crafted envelope claiming half a billion rounds would
        // stall the app for minutes inside PBKDF2 on the import prompt.
        var envelope = try TransferCrypto.seal(["k": "v"], password: "pw", rounds: 1_000)
        envelope.rounds = 500_000_000
        #expect(throws: TransferCrypto.CryptoError.malformedEnvelope) {
            try TransferCrypto.open(envelope, password: "pw")
        }
    }
}

@Suite("Collection transfer format")
struct WorkspaceTransferTests {

    /// Non-empty secret values keyed "<elementID>.<fieldKey>" — the unit the envelope seals.
    private func secretValues(of workspace: NBWorkspace) -> [String: String] {
        var out: [String: String] = [:]
        _ = workspace.mappingSecretValues { elementID, fieldKey, value in
            if !value.isEmpty { out["\(elementID).\(fieldKey)"] = value }
            return value
        }
        return out
    }

    @Test("Secrets survive an export/import round trip with the right password")
    func secretsRoundTrip() throws {
        let source = MockData.workspace()
        let original = secretValues(of: source)
        try #require(!original.isEmpty, "the sample catalogue must carry secrets for this to mean anything")

        let data = try WorkspaceTransfer.exportData(source, password: "pw", rounds: 1_000)
        let file = try WorkspaceTransfer.readFile(from: data)
        let unlocked = try WorkspaceTransfer.unlockingSecrets(of: file, password: "pw")
        #expect(secretValues(of: unlocked) == original)
    }

    @Test("The export bytes carry no plaintext secret")
    func exportBlanksInBand() throws {
        let source = MockData.workspace()
        let secret = try #require(secretValues(of: source).values.first)
        let data = try WorkspaceTransfer.exportData(source, password: "pw", rounds: 1_000)
        #expect(!String(decoding: data, as: UTF8.self).contains(secret))
    }

    @Test("Claims never ride in an export")
    func exportStripsClaims() throws {
        var source = MockData.workspace()
        if let groupID = source.groupOrder.first, var group = source.groups[groupID], !group.elements.isEmpty {
            group.elements[0].claimedBy = NBClaim(who: "someone", minutesAgo: 5)
            source.groups[groupID] = group
        }
        let data = try WorkspaceTransfer.exportData(source, password: "pw", rounds: 1_000)
        let file = try WorkspaceTransfer.readFile(from: data)
        let claims = file.workspace.groups.values.flatMap(\.elements).compactMap(\.claimedBy)
        #expect(claims.isEmpty, "a claim frozen into a file arrives stale by construction")
    }

    @Test("Wrong password on import surfaces as wrongPassword")
    func importWrongPassword() throws {
        let data = try WorkspaceTransfer.exportData(MockData.workspace(), password: "right", rounds: 1_000)
        let file = try WorkspaceTransfer.readFile(from: data)
        #expect(throws: WorkspaceTransfer.ImportError.wrongPassword) {
            try WorkspaceTransfer.unlockingSecrets(of: file, password: "wrong")
        }
    }

    @Test("A secretless catalogue exports without an envelope and imports clean")
    func secretlessExport() throws {
        let source = MockData.emptyWorkspace()
        let data = try WorkspaceTransfer.exportData(source, password: "irrelevant", rounds: 1_000)
        let file = try WorkspaceTransfer.readFile(from: data)
        #expect(file.secrets == nil, "no secret values, no envelope")
        let imported = try WorkspaceTransfer.unlockingSecrets(of: file, password: "whatever")
        #expect(!imported.groups.isEmpty)
    }

    @Test("Any format version other than the current one is refused", arguments: [0, 2, 99])
    func otherVersionsRefused(version: Int) throws {
        // Exact match by design: pre-release there is one format, and files claiming any
        // other version reset expectations at the door instead of being tolerated.
        let workspaceJSON = String(decoding: try JSONEncoder().encode(MockData.emptyWorkspace()), as: UTF8.self)
        let data = Data(#"{"formatVersion":\#(version),"workspace":\#(workspaceJSON)}"#.utf8)
        #expect(throws: WorkspaceTransfer.ImportError.unsupportedVersion(version)) {
            try WorkspaceTransfer.readFile(from: data)
        }
    }

    @Test("Garbage is unreadable, an empty catalogue is refused")
    func badFiles() {
        #expect(throws: WorkspaceTransfer.ImportError.unreadable) {
            try WorkspaceTransfer.readFile(from: Data("not json".utf8))
        }
        let empty = NBWorkspace(name: "e", groupOrder: [], groups: [:], members: [:])
        let data = try? JSONEncoder().encode(WorkspaceTransferFile(workspace: empty))
        #expect(throws: WorkspaceTransfer.ImportError.emptyWorkspace) {
            try WorkspaceTransfer.readFile(from: data ?? Data())
        }
    }
}
