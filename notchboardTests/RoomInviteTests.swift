//
//  RoomInviteTests.swift
//  notchboardTests
//
//  The one-password join design (vision.md §14.3, revised 2026-08-08): the invite
//  paste-code round-trips the room config, and the broker credential rides inside it
//  sealed under the room key — typed once by the host, unsealed by every joiner's
//  engine, never retyped and never stored in plaintext anywhere.
//

import CryptoKit
import Foundation
import Testing
@testable import notchboard

@Suite("Room invite paste-code")
struct RoomInviteCodecTests {

    @Test("Round-trips the address, account username, and sealed credential")
    func roundTrip() throws {
        var config = NBRoomConfig(brokerURL: "mqtts://team@abc123.s1.eu.hivemq.cloud:8883", room: "acme-mobile")
        config.sealedBrokerPassword = Data([1, 2, 3, 4])
        config.firstSyncCompleted = true // this Mac's history — must not travel

        let invite = try #require(RoomInvite.encode(config))
        #expect(invite.hasPrefix("notchboard-room:"))
        #expect(!invite.contains("+") && !invite.contains("/") && !invite.contains("="),
                "base64url, unpadded — Slack linkifies the standard alphabet badly")

        let decoded = try #require(RoomInvite.decode(invite))
        #expect(decoded.brokerURL == config.brokerURL)
        #expect(decoded.room == config.room)
        #expect(decoded.sealedBrokerPassword == Data([1, 2, 3, 4]))
        #expect(decoded.firstSyncCompleted == false, "an invitee has never merged")
    }

    @Test("Tolerates the mess pasting produces")
    func pasteTolerance() throws {
        let invite = try #require(RoomInvite.encode(NBRoomConfig(brokerURL: "mqtt://localhost:1883", room: "dev")))
        #expect(RoomInvite.decode("  \n\(invite)\n ") != nil)
    }

    @Test("Refuses everything that isn't an invite", arguments: [
        "", "notchboard-room:", "notchboard-room:!!!not-base64!!!",
        "https://example.com", "kw3ph-x87mn-qv2tc-e9rju",
    ])
    func refusals(raw: String) {
        #expect(RoomInvite.decode(raw) == nil)
    }

    @Test("Refuses a decoded config whose contents wouldn't survive the setup dialog")
    func refusesGarbageContents() throws {
        // A syntactically valid invite around an unusable address or slug must fail at
        // decode, not at connect — same posture as the setup dialog's validation.
        let encoder = JSONEncoder()
        for bad in [NBRoomConfig(brokerURL: "not a url ://", room: "dev"),
                    NBRoomConfig(brokerURL: "mqtt://localhost:1883", room: "Bad Slug!")] {
            let json = try encoder.encode(bad)
            let base64 = json.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            #expect(RoomInvite.decode("notchboard-room:" + base64) == nil)
        }
    }
}

@Suite("Sealed broker credential lifecycle", .serialized)
struct SealedBrokerCredentialTests {

    private let key = SymmetricKey(data: Data(repeating: 7, count: 32))
    private let config = NBRoomConfig(brokerURL: "mqtts://team@broker.test:8883", room: "cred")

    /// One engine over a loopback broker, with the factory's received broker password
    /// captured — the assertion surface for the whole seal/unseal design.
    @MainActor
    private final class Harness {
        let store: CollectionStore
        let engine: SyncEngine
        let collectionID: String
        private(set) var received: [String?] = []
        private(set) var events: [RoomEvent] = []

        init(broker: LoopbackBroker, memberID: String, workspace: NBWorkspace) {
            let collection = NBCollection(workspace: workspace)
            collectionID = collection.id
            store = CollectionStore(collections: [collection])
            store.selfMemberID = memberID
            var capture: ((String?) -> Void)?
            engine = SyncEngine(store: store, selfMemberID: memberID, selfName: memberID) { _, password in
                capture?(password)
                return broker.makeTransport()
            }
            capture = { [weak self] in self?.received.append($0) }
            engine.onEvent = { [weak self] _, event in self?.events.append(event) }
        }

        var storedRoom: NBRoomConfig? {
            store.collections.first { $0.id == collectionID }?.room
        }
    }

    @MainActor
    private func makeWorkspace(_ name: String) -> NBWorkspace {
        NBWorkspace(name: name, groupOrder: [], groups: [:], members: [:])
    }

    @Test("Host seals once; the invitee's engine unseals without ever being told")
    func sealTravelsAndUnseals() {
        SnapshotStore.directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nb-cred-\(UUID().uuidString)", isDirectory: true)
        // And the key, so no test ever reaches the real login Keychain — reading the real
        // item can block on an approval modal a headless run cannot answer.
        SnapshotStore.deviceKeyOverride = SymmetricKey(data: Data(repeating: 3, count: 32))
        let broker = LoopbackBroker()

        // The host types the broker password exactly once.
        let host = Harness(broker: broker, memberID: "host", workspace: makeWorkspace("host"))
        host.engine.joinRoom(config, password: "", collectionID: host.collectionID,
                             brokerPassword: "hive-cred", preDerivedKey: key)
        broker.pump()
        #expect(host.received == ["hive-cred"], "the transport gets the plaintext it needs to authenticate")
        let sealed = host.storedRoom?.sealedBrokerPassword
        #expect(sealed != nil, "the credential must be sealed into the stored config")
        #expect(sealed.map { String(data: $0, encoding: .utf8) } != "hive-cred",
                "and sealed means ciphertext, not a courtesy copy")

        // The invitee joins from the invite (the stored config), with only the room key.
        let inviteConfig = RoomInvite.decode(RoomInvite.encode(host.storedRoom!)!)!
        let invitee = Harness(broker: broker, memberID: "invitee", workspace: makeWorkspace("invitee"))
        invitee.engine.joinRoom(inviteConfig, password: "", collectionID: invitee.collectionID, preDerivedKey: key)
        broker.pump()
        #expect(invitee.received == ["hive-cred"], "unsealed from the config — nobody retyped it")
    }

    @Test("The wrong room password fails before any connection attempt")
    func wrongKeyFailsClosed() throws {
        let broker = LoopbackBroker()
        var sealedConfig = config
        sealedConfig.sealedBrokerPassword = try RoomCrypto.seal(Data("hive-cred".utf8), key: key)

        let joiner = Harness(broker: broker, memberID: "joiner", workspace: makeWorkspace("joiner"))
        let wrongKey = SymmetricKey(data: Data(repeating: 9, count: 32))
        joiner.engine.joinRoom(sealedConfig, password: "", collectionID: joiner.collectionID, preDerivedKey: wrongKey)
        broker.pump()

        #expect(joiner.received.isEmpty, "no transport may be built around a password known to be garbage")
        #expect(joiner.engine.session(for: joiner.collectionID) == nil)
        #expect(joiner.events.contains { if case .wrongPassword = $0 { return true }; return false })
    }
}
