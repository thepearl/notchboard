//
//  PeerHarnessTests.swift
//  notchboardTests
//
//  The whole stack, twice, against a real broker: two complete peers (CollectionStore +
//  SyncEngine + MQTTSyncTransport) sharing a local mosquitto — the closest a single Mac
//  gets to two teammates until a second human exists (vision.md §14's own sequencing).
//  Everything below this level is proven elsewhere; this suite proves the pieces agree
//  with each other over a real socket.
//
//  Self-skips without a broker on localhost:1883, like MosquittoIntegrationTests.
//  Room keys are pre-derived (SyncWireTests covers the KDF); every wait polls.
//

import CryptoKit
import Foundation
import Network
import Testing
@testable import notchboard

@Suite("Two full peers over real MQTT", .serialized)
@MainActor
struct PeerHarnessTests {

    private static var hasLocalBroker: Bool { BrokerProbe.hasLocalBroker }

    private let key = SymmetricKey(data: Data(repeating: 11, count: 32))
    private let room = "hz-\(UUID().uuidString.prefix(8).lowercased())"
    private var config: NBRoomConfig { NBRoomConfig(brokerURL: "mqtt://localhost:1883", room: room) }

    @MainActor
    private final class Peer {
        let store: CollectionStore
        let engine: SyncEngine
        let collectionID: String
        var events: [RoomEvent] = []

        var session: RoomSession { engine.session(for: collectionID)! }
        var workspace: NBWorkspace { store.collections.first { $0.id == collectionID }!.workspace }

        init(memberID: String, name: String, workspace: NBWorkspace) {
            let collection = NBCollection(workspace: workspace)
            collectionID = collection.id
            store = CollectionStore(collections: [collection])
            store.selfMemberID = memberID
            engine = SyncEngine(store: store, selfMemberID: memberID, selfName: name) { config in
                MQTTSyncTransport(config: config, memberID: memberID)
            }
            store.changeSink = { [weak engine = engine] change in engine?.handleLocalChange(change) }
            engine.onEvent = { [weak self] _, event in self?.events.append(event) }
        }

        func join(config: NBRoomConfig, key: SymmetricKey) {
            engine.joinRoom(config, password: "", collectionID: collectionID, preDerivedKey: key)
        }

        func element(_ id: String) -> NBElement? {
            workspace.groups.values.flatMap(\.elements).first { $0.id == id }
        }
    }

    private func poll(timeout: TimeInterval = 10, until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private func seededWorkspace() -> NBWorkspace {
        func el(_ id: String, _ name: String) -> NBElement {
            NBElement(id: id, name: name, environments: [.dev], isFavorite: false,
                      claimedBy: nil, note: "", lastUsed: "",
                      values: ["username": "\(name)@acme.dev", "password": "pw-\(id)"],
                      updatedAt: Date(timeIntervalSince1970: 1_000), updatedBy: "seed")
        }
        let group = NBGroup(id: "users", label: "users", singular: "user", secondaryKey: "username",
                            fields: [NBField(key: "username", label: "username", type: .text),
                                     NBField(key: "password", label: "password", type: .secret)],
                            elements: [el("h1", "ava"), el("h2", "bo")],
                            updatedAt: Date(timeIntervalSince1970: 500))
        return NBWorkspace(name: "harness", groupOrder: ["users"], groups: ["users": group], members: [:])
    }

    @Test("Seed, adopt, live edit, claim with presence, delete, and a graceful goodbye")
    func fullLifecycle() async throws {
        try #require(Self.hasLocalBroker, "no broker on localhost:1883 — start one with: mosquitto -p 1883")
        SnapshotStore.directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nb-harness-\(UUID().uuidString)", isDirectory: true)

        // ── Ghazi's Mac seeds the room.
        let ghazi = Peer(memberID: "hz-ghazi", name: "ghazi", workspace: seededWorkspace())
        ghazi.join(config: config, key: key)
        await poll { ghazi.engine.session(for: ghazi.collectionID)?.state == .connected }
        #expect(ghazi.session.state == .connected)

        // ── Lina imported the file (same catalogue, re-minted ids) and joins: adopts.
        var imported = seededWorkspace()
        var seen: Set<String> = ["h1", "h2"]
        imported.deduplicateElementIDs(seen: &seen)
        let lina = Peer(memberID: "hz-lina", name: "lina", workspace: imported)
        lina.join(config: config, key: key)
        await poll { lina.engine.session(for: lina.collectionID)?.state == .connected }
        await poll { lina.element("h1") != nil }

        #expect(lina.element("h1")?.name == "ava", "adopted the room's ids, not her re-minted copies")
        #expect(lina.workspace.groups["users"]?.elements.count == 2)
        #expect(lina.element("h1")?.values["password"] == "pw-h1", "secrets crossed the real wire sealed")

        // ── Presence crossed both ways.
        await poll { ghazi.session.onlineMemberIDs == ["hz-lina"] && lina.session.onlineMemberIDs == ["hz-ghazi"] }
        #expect(ghazi.session.onlineMemberIDs == ["hz-lina"])

        // ── A live edit converges.
        ghazi.store.mutate("h1", in: "users") { $0.note = "rotated this morning" }
        await poll { lina.element("h1")?.note == "rotated this morning" }
        #expect(lina.element("h1")?.note == "rotated this morning")

        // ── Lina marks a row in use; Ghazi sees it, attributed by name.
        lina.store.setClaim(NBClaim(who: "hz-lina"), elementID: "h2",
                            group: lina.workspace.groupOrder[0],
                            collection: lina.collectionID, claimantName: "lina")
        await poll { ghazi.element("h2")?.claimedBy?.who == "hz-lina" }
        #expect(ghazi.workspace.members["hz-lina"]?.name == "lina")
        #expect(!ghazi.session.isEffectivelyFree(ghazi.element("h2")!.claimedBy!))

        // ── A deletion travels.
        ghazi.store.deleteElement("h1", from: "users")
        await poll { lina.element("h1") == nil }
        #expect(lina.element("h1") == nil)

        // ── A graceful goodbye flips presence and renders her mark free.
        lina.engine.sleepAll()
        await poll { ghazi.session.onlineMemberIDs.isEmpty }
        #expect(ghazi.session.onlineMemberIDs.isEmpty)
        #expect(ghazi.element("h2")?.claimedBy?.who == "hz-lina", "the mark itself survives her leaving")
        #expect(ghazi.session.isEffectivelyFree(ghazi.element("h2")!.claimedBy!), "…but renders free")

        // ── And she comes back to exactly the state she left, plus what happened since.
        ghazi.store.mutate("h2", in: "users") { $0.note = "changed while lina was away" }
        lina.engine.wakeAll()
        await poll { lina.engine.session(for: lina.collectionID)?.state == .connected }
        await poll { lina.element("h2")?.note == "changed while lina was away" }
        #expect(lina.element("h2")?.note == "changed while lina was away", "wake-up replay is the catch-up")
        #expect(lina.element("h1") == nil, "the deletion held through her absence")

        ghazi.engine.sleepAll()
        lina.engine.sleepAll()
    }
}

