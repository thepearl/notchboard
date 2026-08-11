//
//  SyncModelTests.swift
//  notchboardTests
//
//  Phase A of the sync milestone (vision.md §14.2): the model can now carry conflict
//  resolution — content timestamps, tombstones, change emission from every local mutation
//  primitive, and a remote-apply path that never emits. These tests pin the rules the
//  engine will lean on before any transport exists: LWW with clock clamp and deterministic
//  tie-break, tombstones beating stale edits (and losing to newer ones), and the
//  releaseOrphanedClaims trap — a remote claim must bring its member or vanish at relaunch.
//

import Foundation
import Testing
@testable import notchboard

// MARK: - Fixtures

private func element(
    id: String = UUID().uuidString,
    name: String = "el",
    values: [String: String] = [:],
    updatedAt: Date = Date(timeIntervalSince1970: 1_000),
    updatedBy: String = "peer-a"
) -> NBElement {
    NBElement(id: id, name: name, environments: [.dev], isFavorite: false,
              claimedBy: nil, note: "", lastUsed: "", values: values,
              updatedAt: updatedAt, updatedBy: updatedBy)
}

private func workspace(elements: [NBElement], groupUpdatedAt: Date = Date(timeIntervalSince1970: 500)) -> NBWorkspace {
    let group = NBGroup(id: "users", label: "users", singular: "user", secondaryKey: "username",
                        fields: [NBField(key: "username", label: "username", type: .text)],
                        elements: elements, updatedAt: groupUpdatedAt)
    return NBWorkspace(name: "w", groupOrder: ["users"], groups: ["users": group], members: [:])
}

/// A store seeded with exactly one known element, plus a sink capturing every emission.
private func makeStore(_ elements: [NBElement]) -> (store: CollectionStore, collectionID: String, changes: () -> [SyncChange]) {
    let collection = NBCollection(workspace: workspace(elements: elements))
    let store = CollectionStore(collections: [collection])
    store.selfMemberID = "me"
    let box = ChangeBox()
    store.changeSink = { box.items.append($0) }
    return (store, collection.id, { box.items })
}

/// Reference box so the capture list survives the closure. The suite is main-actor
/// isolated (project default), so plain mutable state is safe.
private final class ChangeBox {
    var items: [SyncChange] = []
}

// MARK: - Emission

@Suite("Change emission from local mutations")
struct ChangeEmissionTests {

    @Test("A content edit stamps updatedAt/updatedBy and emits .element")
    func mutateStampsAndEmits() {
        let old = Date(timeIntervalSince1970: 1_000)
        let el = element(updatedAt: old, updatedBy: "someone-else")
        let (store, cid, changes) = makeStore([el])

        store.mutate(el.id, in: "users") { $0.name = "renamed" }

        let stored = store.element(el.id, group: "users", collection: cid)
        #expect(stored?.updatedAt ?? old > old)
        #expect(stored?.updatedBy == "me")
        guard case .element(let emittedCID, "users", let emitted)? = changes().last else {
            Issue.record("expected an .element emission")
            return
        }
        #expect(emittedCID == cid)
        #expect(emitted.name == "renamed")
    }

    @Test("A no-op edit neither stamps nor emits")
    func noOpMutateIsSilent() {
        let el = element()
        let (store, cid, changes) = makeStore([el])

        store.mutate(el.id, in: "users") { _ in }

        #expect(store.element(el.id, group: "users", collection: cid)?.updatedAt == el.updatedAt,
                "an unchanged element must not be re-stamped into 'edited just now'")
        #expect(changes().isEmpty)
    }

    @Test("setClaim emits .claim and leaves the content timestamp alone")
    func setClaimDoesNotBumpContent() {
        let el = element()
        let (store, cid, changes) = makeStore([el])

        store.setClaim(NBClaim(who: "me"), elementID: el.id, group: "users", collection: cid, claimantName: "ghazi")

        let stored = store.element(el.id, group: "users", collection: cid)
        #expect(stored?.claimedBy?.who == "me")
        #expect(stored?.updatedAt == el.updatedAt,
                "marking a row in use must never fight a teammate's real edit in LWW")
        guard case .claim(_, el.id, let claim?, "ghazi")? = changes().last else {
            Issue.record("expected a .claim emission")
            return
        }
        #expect(claim.who == "me")
    }

    @Test("The favourite star is local-only: no stamp, no emission")
    func favouriteIsLocalOnly() {
        let el = element()
        let (store, cid, changes) = makeStore([el])

        store.mutateLocalOnly(el.id, in: "users") { $0.isFavorite = true }

        #expect(store.element(el.id, group: "users", collection: cid)?.isFavorite == true)
        #expect(store.element(el.id, group: "users", collection: cid)?.updatedAt == el.updatedAt)
        #expect(changes().isEmpty)
    }

    @Test("appendElement stamps ownership and emits")
    func appendStampsAndEmits() {
        let (store, _, changes) = makeStore([])
        store.appendElement(element(updatedBy: "stale"), to: "users")

        guard case .element(_, _, let emitted)? = changes().last else {
            Issue.record("expected an .element emission")
            return
        }
        #expect(emitted.updatedBy == "me")
    }

    @Test("deleteElement leaves a tombstone and emits .elementDeleted")
    func deleteLeavesTombstone() {
        let el = element()
        let (store, cid, changes) = makeStore([el])

        store.deleteElement(el.id, from: "users")

        let stones = store.workspace.tombstones
        #expect(stones.count == 1)
        #expect(stones.first?.kind == .element)
        #expect(stones.first?.id == el.id)
        #expect(stones.first?.by == "me")
        guard case .elementDeleted(cid, "users", el.id, _)? = changes().last else {
            Issue.record("expected an .elementDeleted emission")
            return
        }
    }

    @Test("deleteGroup leaves a group tombstone and names the elements it held")
    func deleteGroupTombstone() {
        let el = element()
        let (store, _, changes) = makeStore([el])

        store.deleteGroup("users")

        #expect(store.workspace.tombstones.first?.kind == .group)
        guard case .groupDeleted(_, "users", let elementIDs, _)? = changes().last else {
            Issue.record("expected a .groupDeleted emission")
            return
        }
        #expect(elementIDs == [el.id], "the engine needs these to clear the retained element topics")
    }

    @Test("Schema edits and group creation emit .schema with the group's position")
    func schemaEmits() {
        let (store, _, changes) = makeStore([])

        store.addGroup(NBGroup(id: "codes", label: "codes", singular: "code", secondaryKey: "code",
                               fields: [NBField(key: "code", label: "code", type: .text)], elements: []))
        guard case .schema(_, let added, let index)? = changes().last else {
            Issue.record("expected a .schema emission from addGroup")
            return
        }
        #expect(added.id == "codes")
        #expect(index == store.workspace.groupOrder.count - 1)

        let fields = store.workspace.groups["users"]!.fields
        #expect(store.applySchema(to: "users", name: "accounts", fields: fields))
        guard case .schema(_, let edited, 0)? = changes().last else {
            Issue.record("expected a .schema emission from applySchema")
            return
        }
        #expect(edited.label == "accounts")
    }

    @Test("Renaming the catalogue stamps and emits .meta")
    func renameEmitsMeta() {
        let (store, cid, changes) = makeStore([])
        // Push the baseline into the past: the rename stamp is truncated to wire
        // precision, so a same-millisecond baseline could tie with it.
        store.workspace.nameUpdatedAt = Date(timeIntervalSince1970: 100)
        let before = store.workspace.nameUpdatedAt

        store.renameActive(to: "team fixtures")

        #expect(store.workspace.nameUpdatedAt > before)
        guard case .meta(cid, "team fixtures", _)? = changes().last else {
            Issue.record("expected a .meta emission")
            return
        }
    }

    @Test("Tombstones survive an encode/decode round trip")
    func tombstoneRoundTrip() throws {
        var ws = workspace(elements: [])
        ws.tombstones = [NBTombstone(kind: .element, id: "x", groupID: "users",
                                     deletedAt: Date(timeIntervalSince1970: 42), by: "me")]
        let data = try JSONEncoder().encode(ws)
        let decoded = try JSONDecoder().decode(NBWorkspace.self, from: data)
        #expect(decoded.tombstones == ws.tombstones)
    }

    @Test("adoptPersisted prunes tombstones past retention and keeps fresh ones")
    func tombstonePrune() {
        var ws = workspace(elements: [element()])
        ws.tombstones = [
            NBTombstone(kind: .element, id: "old", groupID: "users",
                        deletedAt: Date().addingTimeInterval(-NBTombstone.retention - 60), by: "me"),
            NBTombstone(kind: .element, id: "fresh", groupID: "users",
                        deletedAt: Date().addingTimeInterval(-60), by: "me"),
        ]
        let collection = NBCollection(workspace: ws)
        let store = CollectionStore()
        store.adoptPersisted([collection], activeID: collection.id, selfMemberID: "me")
        #expect(store.workspace.tombstones.map(\.id) == ["fresh"])
    }
}

// MARK: - Remote apply

@Suite("Remote apply — LWW and echo suppression")
struct RemoteApplyTests {

    private let base = Date(timeIntervalSince1970: 10_000)

    @Test("A newer remote edit wins and never re-emits")
    func newerRemoteWins() {
        let el = element(updatedAt: base, updatedBy: "peer-a")
        let (store, cid, changes) = makeStore([el])

        var incoming = el
        incoming.name = "remote"
        incoming.updatedAt = base.addingTimeInterval(60)
        incoming.updatedBy = "peer-b"

        let outcome = store.applyRemoteElement(incoming, groupID: "users", collectionID: cid, now: base.addingTimeInterval(120))
        #expect(outcome == .applied)
        #expect(store.element(el.id, group: "users", collection: cid)?.name == "remote")
        #expect(changes().isEmpty, "remote applies must never feed the sink — that is the echo loop")
    }

    @Test("An older remote edit is ignored")
    func olderRemoteIgnored() {
        let el = element(name: "local", updatedAt: base, updatedBy: "peer-a")
        let (store, cid, _) = makeStore([el])

        var incoming = el
        incoming.name = "stale"
        incoming.updatedAt = base.addingTimeInterval(-60)

        #expect(store.applyRemoteElement(incoming, groupID: "users", collectionID: cid, now: base) == .ignored)
        #expect(store.element(el.id, group: "users", collection: cid)?.name == "local")
    }

    @Test("A remote edit from the future is clamped to now before comparing")
    func futureClamped() {
        let el = element(name: "local", updatedAt: base.addingTimeInterval(30), updatedBy: "z-peer")
        let (store, cid, _) = makeStore([el])

        var incoming = el
        incoming.name = "time traveller"
        incoming.updatedAt = base.addingTimeInterval(9_999_999)
        incoming.updatedBy = "a-peer"

        // Clamped to now (base) it is OLDER than the local edit — a skewed clock must not
        // win every conflict permanently.
        #expect(store.applyRemoteElement(incoming, groupID: "users", collectionID: cid, now: base) == .ignored)
        #expect(store.element(el.id, group: "users", collection: cid)?.name == "local")
    }

    @Test("Equal timestamps break on updatedBy, the same way on both peers")
    func tieBreak() {
        let el = element(name: "local", updatedAt: base, updatedBy: "aaa")
        let (store, cid, _) = makeStore([el])

        var incoming = el
        incoming.name = "tied-greater"
        incoming.updatedBy = "zzz"
        #expect(store.applyRemoteElement(incoming, groupID: "users", collectionID: cid, now: base.addingTimeInterval(1)) == .applied)

        var lesser = el
        lesser.name = "tied-lesser"
        lesser.updatedBy = "aaa" // ties with the now-stored "zzz"? no — loses to it
        #expect(store.applyRemoteElement(lesser, groupID: "users", collectionID: cid, now: base.addingTimeInterval(1)) == .ignored)
    }

    @Test("The same payload twice is ignored the second time — idempotent echoes")
    func idempotentEcho() {
        let el = element(updatedAt: base)
        let (store, cid, _) = makeStore([el])

        var incoming = el
        incoming.name = "edit"
        incoming.updatedAt = base.addingTimeInterval(10)
        #expect(store.applyRemoteElement(incoming, groupID: "users", collectionID: cid, now: base.addingTimeInterval(20)) == .applied)
        #expect(store.applyRemoteElement(incoming, groupID: "users", collectionID: cid, now: base.addingTimeInterval(20)) == .ignored)
    }

    @Test("Local favourite and in-use mark survive a remote content edit")
    func personalStatePreserved() {
        let el = element(updatedAt: base)
        let (store, cid, _) = makeStore([el])
        store.mutateLocalOnly(el.id, in: "users") { $0.isFavorite = true }
        store.setClaim(NBClaim(who: "me"), elementID: el.id, group: "users", collection: cid)

        var incoming = el
        incoming.name = "remote edit"
        incoming.updatedAt = base.addingTimeInterval(60)
        _ = store.applyRemoteElement(incoming, groupID: "users", collectionID: cid, now: base.addingTimeInterval(120))

        let stored = store.element(el.id, group: "users", collection: cid)
        #expect(stored?.name == "remote edit")
        #expect(stored?.isFavorite == true, "favourites are personal — a remote edit must not clear the star")
        #expect(stored?.claimedBy?.who == "me", "claims live on their own topic — content payloads must not touch them")
    }

    @Test("A tombstone beats an edit no newer than it")
    func tombstoneBeatsStaleEdit() {
        let el = element(updatedAt: base)
        let (store, cid, _) = makeStore([el])

        #expect(store.applyRemoteElementTombstone(elementID: el.id, groupID: "users", collectionID: cid,
                                                  deletedAt: base.addingTimeInterval(60), by: "peer-b",
                                                  now: base.addingTimeInterval(120)) == .applied)
        #expect(store.element(el.id, group: "users", collection: cid) == nil)

        // The stale copy tries to come back (an offline peer republishing) — refused.
        var stale = el
        stale.updatedAt = base.addingTimeInterval(30)
        #expect(store.applyRemoteElement(stale, groupID: "users", collectionID: cid, now: base.addingTimeInterval(180)) == .ignored)
    }

    @Test("An edit newer than the tombstone resurrects the element and drops the stone")
    func newerEditResurrects() {
        let el = element(updatedAt: base)
        let (store, cid, _) = makeStore([el])
        _ = store.applyRemoteElementTombstone(elementID: el.id, groupID: "users", collectionID: cid,
                                              deletedAt: base.addingTimeInterval(60), by: "peer-b",
                                              now: base.addingTimeInterval(120))

        var revived = el
        revived.name = "back"
        revived.updatedAt = base.addingTimeInterval(90)
        #expect(store.applyRemoteElement(revived, groupID: "users", collectionID: cid, now: base.addingTimeInterval(120)) == .applied)
        #expect(store.element(el.id, group: "users", collection: cid)?.name == "back")
        #expect(store.workspace.tombstones.isEmpty, "a beaten tombstone must not shadow the element at the next launch")
    }

    @Test("A tombstone loses to a newer local edit, which stays for reconcile-push")
    func localNewerEditSurvivesTombstone() {
        let el = element(updatedAt: base.addingTimeInterval(100))
        let (store, cid, _) = makeStore([el])

        #expect(store.applyRemoteElementTombstone(elementID: el.id, groupID: "users", collectionID: cid,
                                                  deletedAt: base.addingTimeInterval(50), by: "peer-b",
                                                  now: base.addingTimeInterval(200)) == .ignored)
        #expect(store.element(el.id, group: "users", collection: cid) != nil)
    }

    @Test("A remote element for an unknown group defers instead of guessing")
    func unknownGroupDefers() {
        let (store, cid, _) = makeStore([])
        #expect(store.applyRemoteElement(element(), groupID: "nowhere", collectionID: cid) == .deferred)
    }
}

@Suite("Remote apply — schema, claims, meta")
struct RemoteApplyStructureTests {

    private let base = Date(timeIntervalSince1970: 10_000)

    @Test("A newer remote schema reshapes the group but keeps local elements")
    func schemaKeepsElements() {
        let el = element(values: ["username": "ava", "legacy": "x"], updatedAt: base)
        let (store, cid, _) = makeStore([el])

        var incoming = store.workspace.groups["users"]!
        incoming.label = "accounts"
        incoming.fields = [NBField(key: "username", label: "e-mail", type: .text)] // "legacy" dropped
        incoming.elements = [] // wire schema payloads never carry elements
        incoming.updatedAt = base.addingTimeInterval(60)

        #expect(store.applyRemoteSchema(incoming, sortIndex: 0, collectionID: cid, now: base.addingTimeInterval(120)) == .applied)
        let group = store.workspace.groups["users"]
        #expect(group?.label == "accounts")
        #expect(group?.elements.count == 1, "local elements must survive a remote schema edit")
        #expect(group?.elements.first?.values["username"] == "ava")
        #expect(group?.elements.first?.values["legacy"] == nil, "values of dropped fields are filtered, as in a local edit")
    }

    @Test("An older remote schema is ignored")
    func staleSchemaIgnored() {
        let (store, cid, _) = makeStore([])
        var incoming = store.workspace.groups["users"]!
        incoming.label = "stale"
        incoming.updatedAt = Date(timeIntervalSince1970: 1) // long before the group's own stamp
        #expect(store.applyRemoteSchema(incoming, sortIndex: 0, collectionID: cid) == .ignored)
        #expect(store.workspace.groups["users"]?.label == "users")
    }

    @Test("An unknown group arrives empty at the sender's position")
    func newGroupInserted() {
        let (store, cid, _) = makeStore([element()])
        let incoming = NBGroup(id: "codes", label: "codes", singular: "code", secondaryKey: "code",
                               fields: [NBField(key: "code", label: "code", type: .text)],
                               elements: [element()], updatedAt: base)

        #expect(store.applyRemoteSchema(incoming, sortIndex: 0, collectionID: cid, now: base.addingTimeInterval(1)) == .applied)
        #expect(store.workspace.groupOrder == ["codes", "users"])
        #expect(store.workspace.groups["codes"]?.elements.isEmpty == true,
                "schema payloads never seed elements — those travel per-element")
    }

    @Test("A remote group tombstone removes the group; a newer schema survives it")
    func groupTombstone() {
        let (store, cid, _) = makeStore([element()])
        let groupStamp = store.workspace.groups["users"]!.updatedAt

        #expect(store.applyRemoteGroupTombstone(groupID: "users", collectionID: cid,
                                                deletedAt: groupStamp.addingTimeInterval(60), by: "peer-b",
                                                now: groupStamp.addingTimeInterval(120)) == .applied)
        #expect(store.workspace.groups["users"] == nil)
        #expect(!store.workspace.groupOrder.contains("users"))

        // And the losing direction: recreate, then send a tombstone older than the schema.
        let fresh = NBGroup(id: "back", label: "back", singular: "back", secondaryKey: "k",
                            fields: [NBField(key: "k", label: "k", type: .text)], elements: [],
                            updatedAt: groupStamp.addingTimeInterval(200))
        _ = store.applyRemoteSchema(fresh, sortIndex: 0, collectionID: cid, now: groupStamp.addingTimeInterval(240))
        #expect(store.applyRemoteGroupTombstone(groupID: "back", collectionID: cid,
                                                deletedAt: groupStamp.addingTimeInterval(150), by: "peer-b",
                                                now: groupStamp.addingTimeInterval(240)) == .ignored)
        #expect(store.workspace.groups["back"] != nil)
    }

    @Test("A remote claim inserts its member — and therefore survives adoptPersisted")
    func remoteClaimSurvivesRelaunch() {
        let el = element()
        let (store, cid, _) = makeStore([el])

        let outcome = store.applyRemoteClaim(NBClaim(who: "lina-id"), claimantName: "lina",
                                             elementID: el.id, collectionID: cid, selfID: "me")
        #expect(outcome == .applied)
        #expect(store.workspace.members["lina-id"]?.name == "lina",
                "a claim without its member is wiped by releaseOrphanedClaims at the next launch")

        // The actual trap, replayed: persist-shaped adopt must keep the claim.
        let survived = CollectionStore()
        survived.adoptPersisted(store.collections, activeID: cid, selfMemberID: "me")
        let claim = survived.workspace.groups["users"]?.elements.first { $0.id == el.id }?.claimedBy
        #expect(claim?.who == "lina-id")
    }

    @Test("A remote release reports the freed element for notify-when-free")
    func remoteReleaseReportsFreed() {
        let el = element()
        let (store, cid, _) = makeStore([el])
        _ = store.applyRemoteClaim(NBClaim(who: "lina-id"), claimantName: "lina",
                                   elementID: el.id, collectionID: cid, selfID: "me")

        let outcome = store.applyRemoteClaim(nil, claimantName: "", elementID: el.id, collectionID: cid, selfID: "me")
        guard case .freed(let freed) = outcome else {
            Issue.record("expected .freed, got \(outcome)")
            return
        }
        #expect(freed.id == el.id)
    }

    @Test("A claim for an element we don't hold yet defers for the replay buffer")
    func unknownClaimDefers() {
        let (store, cid, _) = makeStore([])
        #expect(store.applyRemoteClaim(NBClaim(who: "x"), claimantName: "x",
                                       elementID: "ghost", collectionID: cid, selfID: "me") == .deferred)
    }

    @Test("Meta renames follow LWW on nameUpdatedAt")
    func metaLWW() {
        let (store, cid, _) = makeStore([])
        let localStamp = store.workspace.nameUpdatedAt

        #expect(store.applyRemoteMeta(name: "newer", updatedAt: localStamp.addingTimeInterval(60),
                                      collectionID: cid, now: localStamp.addingTimeInterval(120)) == .applied)
        #expect(store.workspace.name == "newer")
        #expect(store.applyRemoteMeta(name: "older", updatedAt: localStamp.addingTimeInterval(-60),
                                      collectionID: cid, now: localStamp.addingTimeInterval(120)) == .ignored)
        #expect(store.workspace.name == "newer")
    }

    @Test("locateElement finds the owning group — claim topics carry none")
    func locate() {
        let el = element()
        let (store, cid, _) = makeStore([el])
        #expect(store.locateElement(el.id, collectionID: cid) == "users")
        #expect(store.locateElement("ghost", collectionID: cid) == nil)
    }
}
