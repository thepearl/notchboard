//
//  SyncEngineTests.swift
//  notchboardTests
//
//  The convergence properties of the sync engine, proven deterministically over the
//  loopback broker: no network, no timing, every delivery happens inside pump(). Two (or
//  three) full peers — store + engine + session — share a broker exactly the way two Macs
//  will share mosquitto, and every scenario asserts both sides ended identical.
//
//  Peers use a pre-derived room key: PBKDF2's cost is a UX decision, not something to pay
//  per test, and determinism here matters more than exercising the stretch (SyncWireTests
//  covers the derivation itself).
//

import CryptoKit
import Foundation
import Testing
@testable import notchboard

// MARK: - Fixtures

private let roomKey = SymmetricKey(data: Data(repeating: 7, count: 32))
private let wrongKey = SymmetricKey(data: Data(repeating: 9, count: 32))
private let roomConfig = NBRoomConfig(brokerURL: "mqtts://broker.test:8883", room: "team")

private func seedWorkspace() -> NBWorkspace {
    func el(_ id: String, _ name: String) -> NBElement {
        NBElement(id: id, name: name, environments: [.dev], isFavorite: false,
                  claimedBy: nil, note: "", lastUsed: "",
                  values: ["username": "\(name)@acme.dev", "password": "s3cret-\(id)"],
                  updatedAt: Date(timeIntervalSince1970: 1_000).truncatedToMilliseconds, updatedBy: "seed")
    }
    let group = NBGroup(id: "users", label: "users", singular: "user", secondaryKey: "username",
                        fields: [NBField(key: "username", label: "username", type: .text),
                                 NBField(key: "password", label: "password", type: .secret)],
                        elements: [el("e1", "ava"), el("e2", "bo")],
                        updatedAt: Date(timeIntervalSince1970: 500))
    return NBWorkspace(name: "seeded", groupOrder: ["users"], groups: ["users": group], members: [:])
}

private func emptyWorkspace(_ name: String = "blank") -> NBWorkspace {
    NBWorkspace(name: name, groupOrder: [], groups: [:], members: [:])
}

/// Guarantees the next store stamp lands in a LATER millisecond than anything stamped so
/// far — LWW's wire precision is 1ms, and tests that need strict ordering must not gamble
/// on how fast two statements run.
private func nextMillisecond() {
    let target = Date().addingTimeInterval(0.002)
    while Date() < target { /* spin ~2ms; a sleep here would suspend the main actor */ }
}

/// A full peer: store + engine wired the way AppDelegate wires the app.
@MainActor
private final class Peer {
    let store: CollectionStore
    let engine: SyncEngine
    let collectionID: String
    private(set) var events: [RoomEvent] = []
    private let transportBox = TransportBox()

    var transport: LoopbackTransport { transportBox.all.last! }
    var session: RoomSession { engine.session(for: collectionID)! }
    var workspace: NBWorkspace { store.collections.first { $0.id == collectionID }!.workspace }

    init(broker: LoopbackBroker, memberID: String, name: String, workspace: NBWorkspace) {
        let collection = NBCollection(workspace: workspace)
        collectionID = collection.id
        store = CollectionStore(collections: [collection])
        store.selfMemberID = memberID
        let box = transportBox
        engine = SyncEngine(store: store, selfMemberID: memberID, selfName: name) { _ in
            let transport = broker.makeTransport()
            box.all.append(transport)
            return transport
        }
        store.changeSink = { [weak engine] change in engine?.handleLocalChange(change) }
        engine.onEvent = { [weak self] _, event in self?.events.append(event) }
    }

    func join(key: SymmetricKey = roomKey) {
        engine.joinRoom(roomConfig, password: "", collectionID: collectionID, preDerivedKey: key)
    }

    func element(_ id: String) -> NBElement? {
        workspace.groups.values.flatMap(\.elements).first { $0.id == id }
    }
}

@MainActor
private final class TransportBox {
    var all: [LoopbackTransport] = []
}

/// Points SnapshotStore at a scratch directory for the adopt-path tests, which force a
/// snapshot before replacing local state.
private func redirectSnapshots() {
    SnapshotStore.directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("nb-sync-tests-\(UUID().uuidString)", isDirectory: true)
}

// MARK: - Tests

@Suite("Sync engine over loopback", .serialized)
struct SyncEngineTests {

    init() {
        redirectSnapshots()
    }

    /// Standard opening move: A seeds an empty room, B joins fresh and adopts.
    private func seededPair(_ broker: LoopbackBroker) -> (a: Peer, b: Peer) {
        let a = Peer(broker: broker, memberID: "member-a", name: "ana", workspace: seedWorkspace())
        a.join()
        broker.pump()
        let b = Peer(broker: broker, memberID: "member-b", name: "bo", workspace: emptyWorkspace())
        b.join()
        broker.pump()
        return (a, b)
    }

    @Test("An empty room is seeded; a fresh joiner adopts the room's state wholesale")
    func seedAndAdopt() {
        let broker = LoopbackBroker()
        let (a, b) = seededPair(broker)

        #expect(a.session.state == .connected)
        #expect(b.session.state == .connected)
        #expect(b.workspace.name == "seeded", "meta travels")
        #expect(b.workspace.groups["users"]?.elements.count == 2)
        #expect(b.element("e1")?.values["password"] == "s3cret-e1", "secret values arrive through the sealed payload")
        #expect(b.events.contains { if case .adoptedRoomState = $0 { return true }; return false })
        // Presence crossed both ways.
        #expect(a.session.onlineMemberIDs == ["member-b"])
        #expect(b.session.onlineMemberIDs == ["member-a"])
    }

    @Test("Two teammates importing the same file don't double the catalogue — re-minted ids are discarded for the room's")
    func duplicateImportAdopts() {
        let broker = LoopbackBroker()
        let a = Peer(broker: broker, memberID: "member-a", name: "ana", workspace: seedWorkspace())
        a.join()
        broker.pump()

        // B "imported the same file": same content, but cross-collection dedup re-minted
        // every element id (they collided with A's at import time on B's Mac).
        var duplicate = seedWorkspace()
        var seen: Set<String> = ["e1", "e2"]
        duplicate.deduplicateElementIDs(seen: &seen)
        let b = Peer(broker: broker, memberID: "member-b", name: "bo", workspace: duplicate)
        b.join()
        broker.pump()

        let bIDs = Set(b.workspace.groups.values.flatMap { $0.elements.map(\.id) })
        #expect(bIDs == ["e1", "e2"], "the room's ids win — no second copy of every row")
        #expect(b.workspace.groups["users"]?.elements.count == 2)
    }

    @Test("A live edit converges")
    func liveEdit() {
        let broker = LoopbackBroker()
        let (a, b) = seededPair(broker)

        a.store.mutate("e1", in: "users") { $0.name = "renamed" }
        broker.pump()

        #expect(b.element("e1")?.name == "renamed")
        #expect(a.element("e1")?.name == "renamed")
    }

    @Test("Concurrent edits of one element resolve the same way on both peers")
    func concurrentEditLWW() {
        let broker = LoopbackBroker()
        let (a, b) = seededPair(broker)

        a.store.mutate("e1", in: "users") { $0.name = "a-edit" }
        nextMillisecond()
        b.store.mutate("e1", in: "users") { $0.name = "b-edit" }
        broker.pump()

        #expect(a.element("e1")?.name == "b-edit", "the later edit wins everywhere")
        #expect(b.element("e1")?.name == "b-edit")
    }

    @Test("A deletion survives the target being offline — the tombstone trap")
    func tombstoneSurvivesOfflinePeer() {
        let broker = LoopbackBroker()
        let (a, b) = seededPair(broker)

        broker.partition(b.transport)
        b.store.mutate("e2", in: "users") { $0.note = "stale offline edit" }
        nextMillisecond()
        a.store.deleteElement("e2", from: "users")
        broker.pump()

        broker.heal(b.transport)
        broker.pump()

        #expect(a.element("e2") == nil)
        #expect(b.element("e2") == nil, "an offline peer must not resurrect a deleted element")
        #expect(b.workspace.tombstones.contains { $0.id == "e2" }, "the tombstone itself replicated")
    }

    @Test("An edit newer than the deletion resurrects the element on both peers")
    func newerEditResurrects() {
        let broker = LoopbackBroker()
        let (a, b) = seededPair(broker)

        broker.partition(b.transport)
        a.store.deleteElement("e2", from: "users")
        broker.pump()
        nextMillisecond()
        b.store.mutate("e2", in: "users") { $0.name = "kept working on it" }

        broker.heal(b.transport)
        broker.pump()

        #expect(a.element("e2")?.name == "kept working on it", "the newer edit beats the tombstone everywhere")
        #expect(b.element("e2")?.name == "kept working on it")
    }

    @Test("A late joiner replays claims that arrive before their elements")
    func lateJoinerClaimOrdering() {
        let broker = LoopbackBroker()
        let (a, _) = seededPair(broker)
        a.store.setClaim(NBClaim(who: "member-a"), elementID: "e1", group: "users",
                         collection: a.collectionID, claimantName: "ana")
        broker.pump()

        // The loopback replays retained topics in sorted order, and "claim" < "el" — so
        // the claim genuinely reaches the joiner before the element it marks.
        let c = Peer(broker: broker, memberID: "member-c", name: "cam", workspace: emptyWorkspace())
        c.join()
        broker.pump()

        #expect(c.element("e1")?.claimedBy?.who == "member-a")
        #expect(c.workspace.members["member-a"]?.name == "ana", "the claimant arrived as a member — the relaunch-wipe trap")
    }

    @Test("A converged room is quiet: one edit costs exactly one publish, no echoes")
    func noEchoLoops() {
        let broker = LoopbackBroker()
        let (a, _) = seededPair(broker)

        let before = broker.publishCount
        a.store.mutate("e1", in: "users") { $0.note = "one change" }
        broker.pump()

        #expect(broker.publishCount == before + 1, "an edit is one publish; anything more is an echo loop")
    }

    @Test("Releasing clears the retained claim; the peer hears the element freed")
    func claimReleaseClearsRetained() {
        let broker = LoopbackBroker()
        let (a, b) = seededPair(broker)
        let claimTopic = SyncTopic.claim(elementID: "e1").string(room: "team")

        a.store.setClaim(NBClaim(who: "member-a"), elementID: "e1", group: "users",
                         collection: a.collectionID, claimantName: "ana")
        broker.pump()
        #expect(broker.retained[claimTopic] != nil)
        #expect(b.element("e1")?.claimedBy?.who == "member-a")

        a.store.setClaim(nil, elementID: "e1", group: "users", collection: a.collectionID)
        broker.pump()
        #expect(broker.retained[claimTopic] == nil, "free = no retained message, the one legitimate empty-payload delete")
        #expect(b.element("e1")?.claimedBy == nil)
        #expect(b.events.contains { if case .elementFreed(let el) = $0 { return el.id == "e1" }; return false },
                "the notify-when-free trigger")
    }

    @Test("An offline claimant's mark renders free without mutating data, and returns with them")
    func offlineClaimantRendersFree() {
        let broker = LoopbackBroker()
        let (a, b) = seededPair(broker)
        b.store.setClaim(NBClaim(who: "member-b"), elementID: "e1", group: "users",
                         collection: b.collectionID, claimantName: "bo")
        broker.pump()

        let claim = a.element("e1")!.claimedBy!
        #expect(!a.session.isEffectivelyFree(claim), "online holder — genuinely in use")

        broker.partition(b.transport) // ungraceful: the last will flips presence
        broker.pump()
        #expect(a.session.onlineMemberIDs.isEmpty)
        #expect(a.session.isEffectivelyFree(claim), "offline holder renders free")
        #expect(a.element("e1")?.claimedBy?.who == "member-b", "presence flicker must never delete the claim")
        #expect(a.events.contains { if case .elementFreed(let el) = $0 { return el.id == "e1" }; return false })

        broker.heal(b.transport)
        broker.pump()
        #expect(a.session.onlineMemberIDs == ["member-b"])
        #expect(!a.session.isEffectivelyFree(claim), "back online — in use again, from data that never changed")
    }

    @Test("Offline work reconcile-pushes on reconnect: new elements and deletions both arrive")
    func reconcilePushAfterPartition() {
        let broker = LoopbackBroker()
        let (a, b) = seededPair(broker)

        broker.partition(b.transport)
        b.store.appendElement(
            NBElement(id: "e3", name: "cyn", environments: [.dev], isFavorite: false,
                      claimedBy: nil, note: "", lastUsed: "", values: ["username": "cyn@acme.dev"]),
            to: "users"
        )
        nextMillisecond()
        b.store.deleteElement("e2", from: "users")

        broker.heal(b.transport)
        broker.pump()

        #expect(a.element("e3")?.name == "cyn", "the offline add reached the peer")
        #expect(a.element("e2") == nil, "the offline delete reached the peer")
        #expect(b.element("e3") != nil)
    }

    @Test("The wire is ciphertext: no plaintext value survives sealing")
    func wireIsCiphertext() {
        let broker = LoopbackBroker()
        _ = seededPair(broker)

        let elementTopic = SyncTopic.element(groupID: "users", elementID: "e1").string(room: "team")
        let payload = broker.retained[elementTopic]!.payload
        for leak in ["ava", "s3cret", "username", "users"] {
            #expect(payload.range(of: Data(leak.utf8)) == nil, "“\(leak)” must not be readable on the broker")
        }
        #expect(throws: TransferCrypto.CryptoError.wrongPassword) {
            try RoomCrypto.open(payload, key: wrongKey)
        }
    }

    @Test("The wrong room password fails loudly BEFORE touching the local catalogue")
    func wrongPasswordFailsClosed() {
        let broker = LoopbackBroker()
        let a = Peer(broker: broker, memberID: "member-a", name: "ana", workspace: seedWorkspace())
        a.join()
        broker.pump()

        let c = Peer(broker: broker, memberID: "member-c", name: "cam", workspace: seedWorkspace())
        c.join(key: wrongKey)
        broker.pump()

        #expect(c.session.state == .failed("wrong room password"))
        #expect(c.events.contains(.wrongPassword))
        #expect(c.workspace.groups["users"]?.elements.count == 2,
                "a typo in the password must never cost the local catalogue")
    }

    @Test("A schema edit travels: relabel arrives, local elements survive")
    func schemaEditTravels() {
        let broker = LoopbackBroker()
        let (a, b) = seededPair(broker)

        nextMillisecond() // the seed's group stamp must lose to this edit
        var fields = a.workspace.groups["users"]!.fields
        fields[0].label = "e-mail"
        #expect(a.store.applySchema(to: "users", name: "accounts", fields: fields))
        broker.pump()

        #expect(b.workspace.groups["users"]?.label == "accounts")
        #expect(b.workspace.groups["users"]?.fields.first?.label == "e-mail")
        #expect(b.workspace.groups["users"]?.elements.count == 2, "a remote schema edit keeps the elements")
    }

    @Test("Deleting a group clears its element topics from the broker")
    func groupDeleteTidiesBroker() {
        let broker = LoopbackBroker()
        let (a, b) = seededPair(broker)

        a.store.deleteGroup("users")
        broker.pump()

        #expect(b.workspace.groups["users"] == nil)
        let elementTopic = SyncTopic.element(groupID: "users", elementID: "e1").string(room: "team")
        #expect(broker.retained[elementTopic] == nil, "orphaned element topics are cleared, not retained forever")
        let schemaTopic = SyncTopic.schema(groupID: "users").string(room: "team")
        #expect(broker.retained[schemaTopic] != nil, "the group tombstone IS retained — it's the deletion's proof")
    }

    @Test("Suspend publishes offline presence gracefully; resume rejoins and re-reads the room")
    func suspendAndResume() {
        let broker = LoopbackBroker()
        let (a, b) = seededPair(broker)

        b.engine.sleepAll()
        broker.pump()
        #expect(a.session.onlineMemberIDs.isEmpty, "a closing lid says goodbye without waiting for the will")
        #expect(b.session.state == .disconnected)

        a.store.mutate("e1", in: "users") { $0.name = "changed while b slept" }
        broker.pump()

        b.engine.wakeAll()
        broker.pump()
        #expect(b.session.state == .connected)
        #expect(b.element("e1")?.name == "changed while b slept", "wake-up replay IS the catch-up")
        #expect(a.session.onlineMemberIDs == ["member-b"])
    }
}
