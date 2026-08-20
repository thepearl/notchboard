//
//  CollectionTests.swift
//  notchboardTests
//
//  Phase 2 coverage: the NBCollection wrapper, the multi-collection view model facade,
//  and the local identity that claims now bind to (vision.md §14.2). The invariant these
//  guard hardest: element ids stay unique across ALL collections, because Keychain
//  account keys carry no collection component.
//

import Foundation
import Testing
@testable import notchboard

@Suite("NBCollection model")
struct NBCollectionModelTests {

    @Test("A payload without local-only fields decodes with fresh defaults")
    func lenientDecoding() throws {
        // The workspace itself stays strict (tombstones is a required key — the no-compat
        // rule); it is only the collection's local-only fields that heal with defaults.
        let json = #"{"workspace":{"name":"w","nameUpdatedAt":0,"groupOrder":[],"groups":{},"members":{},"tombstones":[]}}"#
        let collection = try JSONDecoder().decode(NBCollection.self, from: Data(json.utf8))
        #expect(!collection.id.isEmpty)
        #expect(collection.deeplinkScheme.isEmpty)
        #expect(collection.room == nil)
    }

    @Test("Decoding the same payload twice yields two distinct local ids")
    func idIsLocal() throws {
        let json = Data(#"{"workspace":{"name":"w","nameUpdatedAt":0,"groupOrder":[],"groups":{},"members":{},"tombstones":[]}}"#.utf8)
        let first = try JSONDecoder().decode(NBCollection.self, from: json)
        let second = try JSONDecoder().decode(NBCollection.self, from: json)
        #expect(first.id != second.id, "the id must be local so importing an export twice yields two collections")
    }

    @Test("name is a passthrough to the workspace, so the two can't drift")
    func namePassthrough() {
        var collection = NBCollection(workspace: MockData.emptyWorkspace(name: "before"))
        collection.name = "after"
        #expect(collection.workspace.name == "after")
    }

    @Test("Element-id dedup spans collections")
    func dedupAcrossCollections() {
        // The sample workspace uses fixed UUID literals, so two copies collide on every id.
        var collections = [
            NBCollection(workspace: MockData.workspace()),
            NBCollection(workspace: MockData.workspace()),
        ]
        collections.deduplicateElementIDsAcrossCollections()
        let ids = collections.flatMap { $0.workspace.groups.values.flatMap { $0.elements.map(\.id) } }
        #expect(Set(ids).count == ids.count)
    }

    @Test("The prune keeping-set spans every collection — the landmine")
    func keychainKeysSpanCollections() {
        // This is the test the plan says would have caught AppDelegate passing only the
        // active collection's keys to pruneOrphans, which would have deleted every other
        // collection's secrets on the next launch.
        let a = NBCollection(workspace: tinyWorkspace(name: "a", elementID: "el-a", secretValue: "sa"))
        let b = NBCollection(workspace: tinyWorkspace(name: "b", elementID: "el-b", secretValue: "sb"))
        let keys = Set([a, b].allSecretKeychainKeys)
        #expect(keys.contains("el-a.password"))
        #expect(keys.contains("el-b.password"))
    }
}

@Suite("Collections in the view model")
struct CollectionViewModelTests {

    @Test("createCollection appends, switches, and is immediately usable")
    func createAndSwitch() {
        let vm = NotchboardViewModel()
        let firstID = vm.activeCollectionID
        vm.createCollection(named: "acme-app")
        #expect(vm.collections.count == 2)
        #expect(vm.activeCollectionID != firstID)
        #expect(vm.workspace.name == "acme-app")
        #expect(!vm.activeGroup.fields.isEmpty, "an empty collection still has one usable group")
    }

    @Test("Switching collections resets transient panel state")
    func switchResets() {
        let vm = NotchboardViewModel()
        let firstID = vm.activeCollectionID
        guard let element = vm.activeGroup.elements.first else {
            Issue.record("seed data has no elements")
            return
        }
        vm.openDetail(element)
        vm.searchText = "query"
        vm.toggleReveal(elementID: element.id, fieldKey: "password")
        vm.createCollection(named: "second")

        #expect(vm.currentView == .list)
        #expect(vm.searchText.isEmpty)
        #expect(vm.revealedFieldKeys.isEmpty)

        vm.switchCollection(firstID)
        #expect(vm.workspace.name == MockData.workspace().name, "switching back restores the first catalogue")
    }

    @Test("The deeplink scheme travels with its collection")
    func schemePerCollection() {
        let vm = NotchboardViewModel()
        let firstID = vm.activeCollectionID
        vm.deeplinkScheme = "brewly"
        vm.createCollection(named: "other")
        #expect(vm.deeplinkScheme.isEmpty, "a new collection starts unconfigured")
        vm.deeplinkScheme = "notchdemo"
        vm.switchCollection(firstID)
        #expect(vm.deeplinkScheme == "brewly", "switching collections switches the app you deeplink into")
    }

    @Test("Mutations through the facade land only in the active collection")
    func facadeIsolation() {
        let vm = NotchboardViewModel()
        let firstID = vm.activeCollectionID
        let countBefore = vm.workspace.elementCount
        vm.createCollection(named: "second")
        vm.openAdd()
        vm.elementForm.name = "only in second"
        vm.saveElement()
        #expect(vm.workspace.elementCount == 1)
        vm.switchCollection(firstID)
        #expect(vm.workspace.elementCount == countBefore)
    }

    @Test("Duplicate copies values and scheme but never element ids")
    func duplicateRemapsIDs() {
        let vm = NotchboardViewModel()
        vm.deeplinkScheme = "brewly"
        let originalIDs = Set(vm.workspace.groups.values.flatMap { $0.elements.map(\.id) })
        vm.duplicateActiveCollection()
        #expect(vm.workspace.name.hasSuffix(" copy"))
        #expect(vm.deeplinkScheme == "brewly")
        let copyIDs = Set(vm.workspace.groups.values.flatMap { $0.elements.map(\.id) })
        #expect(copyIDs.count == originalIDs.count)
        #expect(originalIDs.isDisjoint(with: copyIDs), "shared ids would alias secrets in the Keychain")
    }

    @Test("The last collection cannot be deleted")
    func deleteRefusesLast() {
        let vm = NotchboardViewModel()
        vm.deleteActiveCollection()
        #expect(vm.collections.count == 1)
    }

    @Test("Deleting the active collection lands on a remaining one")
    func deleteLandsOnRemaining() {
        let vm = NotchboardViewModel()
        let firstID = vm.activeCollectionID
        vm.createCollection(named: "doomed")
        vm.deleteActiveCollection()
        #expect(vm.collections.count == 1)
        #expect(vm.activeCollectionID == firstID)
    }

    @Test("addCollection imports alongside, never destroying, and dedups ids")
    func addCollectionAppends() {
        let vm = NotchboardViewModel()
        let before = vm.collections.count
        vm.addCollection(MockData.workspace()) // same fixed ids as the seed — must remap
        #expect(vm.collections.count == before + 1)
        let all = vm.collections.flatMap { $0.workspace.groups.values.flatMap { $0.elements.map(\.id) } }
        #expect(Set(all).count == all.count, "cross-collection element ids must stay unique")
    }

    @Test("restoreCollections replaces everything — the snapshot recovery path")
    func snapshotRestoreReplaces() {
        let vm = NotchboardViewModel()
        vm.createCollection(named: "junk")
        let snapshot = [NBCollection(workspace: MockData.emptyWorkspace(name: "restored"))]
        vm.restoreCollections(snapshot, activeID: snapshot[0].id)
        #expect(vm.collections.count == 1)
        #expect(vm.workspace.name == "restored")
    }
}

@Suite("Local identity")
struct IdentityTests {

    @Test("The member id survives a persist/restore round trip")
    func memberIDStable() {
        let vm = NotchboardViewModel()
        let id = vm.selfMemberID
        let state = vm.persistableState(onboardingCompleted: true, onboardingName: "x")
        let vm2 = NotchboardViewModel()
        vm2.restore(from: state)
        #expect(vm2.selfMemberID == id)
    }

    @Test("Claims are labelled with the onboarding first name, falling back to you")
    func claimLabel() {
        let vm = NotchboardViewModel()
        vm.updateSelfName("John Doe")
        #expect(vm.selfClaimLabel == "john")
        // memberName resolves the local member id through the same label, so both must
        // give the *first* name — the row badge reads "● john", never a surname.
        #expect(vm.memberName(vm.selfMemberID) == "john")
        vm.updateSelfName("   ")
        #expect(vm.selfClaimLabel == "you")
    }

    @Test("The auto-release sweep reaches background collections")
    func sweepReachesBackgroundCollections() {
        let vm = NotchboardViewModel()
        vm.autoReleaseMinutes = 5
        guard let target = vm.activeGroup.elements.first else {
            Issue.record("seed data has no elements")
            return
        }
        var group = vm.activeGroup
        let idx = group.elements.firstIndex { $0.id == target.id }!
        group.elements[idx].claimedBy = NBClaim(who: vm.selfMemberID, minutesAgo: 60)
        vm.workspace.groups[vm.activeGroupID] = group

        vm.createCollection(named: "front") // the stale claim is now in a background collection
        vm.releaseExpiredClaims()

        let survivors = vm.collections
            .flatMap { $0.workspace.groups.values.flatMap(\.elements) }
            .compactMap(\.claimedBy)
        #expect(survivors.isEmpty, "an idle claim must auto-release even while its collection is in the background")
    }
}

/// A one-element workspace with a secret field, for tests that need exact keychain keys.
private func tinyWorkspace(name: String, elementID: String, secretValue: String) -> NBWorkspace {
    let fields = [
        NBField(key: "username", label: "username", type: .text),
        NBField(key: "password", label: "password", type: .secret),
    ]
    let element = NBElement(
        id: elementID, name: "acct", environments: [.dev], isFavorite: false, claimedBy: nil,
        note: "", lastUsed: "", values: ["username": "u", "password": secretValue]
    )
    let group = NBGroup(
        id: "users", label: "users", singular: "user",
        secondaryKey: "username", fields: fields, elements: [element]
    )
    return NBWorkspace(name: name, groupOrder: ["users"], groups: ["users": group], members: [:])
}
