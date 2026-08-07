//
//  SyncWireTests.swift
//  notchboardTests
//
//  The room wire format (SyncPayloads) and the room key (RoomCrypto): everything a
//  payload does between "the store emitted a change" and "bytes on the broker" — sealed
//  always, tombstones distinguishable from content, unknown values degrading instead of
//  failing, and the wrong password failing closed.
//
//  PBKDF2 rounds are dialled way down throughout (the exportData(rounds:) precedent) —
//  the real cost is a UX decision, not something the suite should pay hundreds of times.
//

import CryptoKit
import Foundation
import Testing
@testable import notchboard

private let testKey = try! RoomCrypto.deriveKey(password: "pw", brokerHost: "broker.test", room: "team", rounds: 1_000)

@Suite("Sync topics")
struct SyncTopicTests {

    @Test("Every topic round-trips through its own parser", arguments: [
        SyncTopic.meta,
        .schema(groupID: "users"),
        .element(groupID: "users", elementID: "e1"),
        .claim(elementID: "e1"),
        .presence(memberID: "m1"),
        .syncBarrier(memberID: "m1"),
    ])
    func roundTrip(topic: SyncTopic) {
        let string = topic.string(room: "team")
        #expect(SyncTopic.parse(string, room: "team") == topic)
    }

    @Test("Foreign and malformed topics parse to nil, never crash", arguments: [
        "nb/other-room/meta",           // another room on a shared broker
        "unrelated/topic",              // not ours at all
        "nb/team/el/users",             // element topic missing its element id
        "nb/team/unknown/x",            // a segment this build doesn't know
        "nb/team",                      // bare root
    ])
    func foreignTopicsIgnored(topic: String) {
        #expect(SyncTopic.parse(topic, room: "team") == nil)
    }
}

@Suite("Room crypto")
struct RoomCryptoTests {

    @Test("Seal/open round-trips, and the wire bytes are not the plaintext")
    func roundTrip() throws {
        let secret = Data("the catalogue".utf8)
        let sealed = try RoomCrypto.seal(secret, key: testKey)
        #expect(!sealed.contains(secret.first!) || sealed != secret, "sealed bytes must not be the plaintext")
        #expect(try RoomCrypto.open(sealed, key: testKey) == secret)
    }

    @Test("The wrong password fails closed as wrongPassword, never garbage")
    func wrongKeyFailsClosed() throws {
        let sealed = try RoomCrypto.seal(Data("x".utf8), key: testKey)
        let wrongKey = try RoomCrypto.deriveKey(password: "not-pw", brokerHost: "broker.test", room: "team", rounds: 1_000)
        #expect(throws: TransferCrypto.CryptoError.wrongPassword) {
            try RoomCrypto.open(sealed, key: wrongKey)
        }
    }

    @Test("The salt is deterministic per broker+room, so members need no handshake")
    func deterministicSalt() {
        #expect(RoomCrypto.roomSalt(brokerHost: "h", room: "r") == RoomCrypto.roomSalt(brokerHost: "h", room: "r"))
        #expect(RoomCrypto.roomSalt(brokerHost: "h", room: "r") != RoomCrypto.roomSalt(brokerHost: "h", room: "r2"))
        #expect(RoomCrypto.roomSalt(brokerHost: "h", room: "r") != RoomCrypto.roomSalt(brokerHost: "h2", room: "r"))
    }

    @Test("The same password in a different room derives an unrelated key")
    func perRoomKeys() throws {
        let sealed = try RoomCrypto.seal(Data("x".utf8), key: testKey)
        let otherRoom = try RoomCrypto.deriveKey(password: "pw", brokerHost: "broker.test", room: "other", rounds: 1_000)
        #expect(throws: TransferCrypto.CryptoError.wrongPassword) {
            try RoomCrypto.open(sealed, key: otherRoom)
        }
    }

    @Test("Tampered ciphertext is refused — GCM authenticates")
    func tamperRefused() throws {
        var sealed = try RoomCrypto.seal(Data("x".utf8), key: testKey)
        sealed[sealed.count - 1] ^= 0xFF
        #expect(throws: TransferCrypto.CryptoError.self) {
            try RoomCrypto.open(sealed, key: testKey)
        }
    }
}

@Suite("Sync payload codec")
struct SyncCodecTests {

    private let codec = SyncCodec(key: testKey)

    private var sampleElement: NBElement {
        NBElement(id: "e1", name: "ava", environments: [.dev, .stg], isFavorite: true,
                  claimedBy: NBClaim(who: "me"), note: "n", lastUsed: "yesterday",
                  values: ["username": "ava@acme.dev", "password": "s3cret"],
                  updatedAt: Date(timeIntervalSince1970: 1_000), updatedBy: "me")
    }

    @Test("An element round-trips its content and sheds its personal state")
    func elementRoundTrip() throws {
        let sealed = try codec.seal(SyncElementPayload(element: sampleElement))
        let message = try codec.openTopicMessage(SyncElementPayload.self, from: sealed)
        guard case .content(let payload) = message else {
            Issue.record("expected content")
            return
        }
        let landed = payload.toElement()
        #expect(landed.name == "ava")
        #expect(landed.environments == [.dev, .stg])
        #expect(landed.values["password"] == "s3cret", "secret values ride in-band — the whole payload is ciphertext")
        #expect(landed.updatedAt == Date(timeIntervalSince1970: 1_000), "millisecond dates must survive exactly — LWW compares them")
        #expect(landed.isFavorite == false, "favourites are personal and never travel")
        #expect(landed.claimedBy == nil, "claims have their own topic")
    }

    @Test("A tombstone on the element topic is recognised as one")
    func tombstoneDiscriminated() throws {
        let stone = SyncTombstonePayload(deletedAt: Date(timeIntervalSince1970: 2_000), by: "me")
        let sealed = try codec.seal(stone)
        let message = try codec.openTopicMessage(SyncElementPayload.self, from: sealed)
        #expect(message == .tombstone(stone))
    }

    @Test("A schema round-trips, and an unknown field type degrades to text")
    func schemaRoundTrip() throws {
        let group = NBGroup(id: "users", label: "users", singular: "user", secondaryKey: "username",
                            fields: [NBField(key: "username", label: "username", type: .secret)],
                            elements: [sampleElement], updatedAt: Date(timeIntervalSince1970: 500))
        var payload = SyncSchemaPayload(group: group, sortIndex: 3, by: "me")
        payload.fields[0].type = "holographic" // a field type from some future build

        let opened = try codec.open(SyncSchemaPayload.self, from: try codec.seal(payload))
        let landed = opened.toGroup()
        #expect(landed.fields[0].type == .text, "an unknown type must degrade, not sink the schema")
        #expect(landed.elements.isEmpty, "schema payloads never carry elements")
        #expect(opened.sortIndex == 3)
    }

    @Test("Unknown environments are dropped; an emptied set lands as dev; .all is refused")
    func environmentDegradation() throws {
        var payload = SyncElementPayload(element: sampleElement)
        payload.environments = ["QUANTUM", "ALL"]
        let landed = try codec.open(SyncElementPayload.self, from: try codec.seal(payload)).toElement()
        #expect(landed.environments == [.dev], "unknown + sentinel must degrade to a renderable element")
    }

    @Test("Unknown JSON keys are ignored — two app versions share a room")
    func unknownKeysIgnored() throws {
        var json = try JSONSerialization.jsonObject(
            with: SyncCodec.encoder.encode(SyncClaimPayload(memberID: "m", name: "tom", at: Date())),
            options: []
        ) as! [String: Any]
        json["futureField"] = ["deeply": "nested"]
        let sealed = try RoomCrypto.seal(try JSONSerialization.data(withJSONObject: json), key: testKey)
        let opened = try codec.open(SyncClaimPayload.self, from: sealed)
        #expect(opened.memberID == "m")
    }

    @Test("Presence and meta payloads round-trip")
    func smallPayloads() throws {
        let presence = SyncPresencePayload(name: "tom", state: .online, at: Date(timeIntervalSince1970: 3_000))
        #expect(try codec.open(SyncPresencePayload.self, from: try codec.seal(presence)) == presence)

        let meta = SyncMetaPayload(name: "team fixtures", updatedAt: Date(timeIntervalSince1970: 4_000), by: "me")
        #expect(try codec.open(SyncMetaPayload.self, from: try codec.seal(meta)) == meta)
    }
}
