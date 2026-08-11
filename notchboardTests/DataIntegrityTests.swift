//
//  DataIntegrityTests.swift
//  notchboardTests
//
//  Regression guards for the data-integrity audit findings: the phantom empty-string
//  group, field-key collisions in the schema designer, duplicate IDs from imported or
//  hand-edited files, the restore-time clamps, and the Keychain round trip.
//

import Foundation
import Testing
@testable import notchboard

@Suite("Phantom group prevention")
struct PhantomGroupTests {

    private func viewModelWithNoGroups() -> NotchboardViewModel {
        let vm = NotchboardViewModel()
        for id in vm.workspace.groupOrder {
            vm.deleteGroup(id)
        }
        return vm
    }

    @Test("Deleting every group leaves no phantom path into saveElement")
    func saveElementWithNoGroupsIsRefused() {
        let vm = viewModelWithNoGroups()
        #expect(vm.workspace.groups.isEmpty)

        // Force the form open (openAdd refuses politely, but a stale view could still
        // reach saveElement) and try to save.
        vm.currentView = .add
        vm.elementForm.name = "orphan element"
        vm.saveElement()

        #expect(vm.workspace.groups[""] == nil)
        #expect(vm.workspace.groups.isEmpty)
    }

    @Test("openAdd with no groups refuses instead of opening a schema-less form")
    func openAddWithNoGroupsRefused() {
        let vm = viewModelWithNoGroups()
        vm.openAdd()
        #expect(vm.currentView != .add)
    }

    @Test("saveElement with a stale activeGroupID writes into a real group, not a phantom")
    func saveElementWithStaleActiveGroup() {
        let vm = NotchboardViewModel()
        let realGroupID = vm.workspace.groupOrder[0]
        vm.activeGroupID = "ghost-group"
        vm.currentView = .add
        vm.elementForm.name = "element via stale id"
        vm.saveElement()
        #expect(vm.workspace.groups["ghost-group"] == nil)
        #expect(vm.workspace.groups[realGroupID]?.elements.contains { $0.name == "element via stale id" } == true)
    }

    /// The audit's headline finding: the list rendered a fallback group while every element
    /// mutation still addressed the stale stored id, so the store dropped the write and the
    /// user's click did nothing at all — no change, no toast, no error. A teammate deleting
    /// the group you are looking at is the way into that state, and nothing repaired it.
    @Test("A remote group deletion leaves element actions working on what the list shows")
    func mutationsFollowTheRenderedGroupAfterRemoteDeletion() {
        let vm = NotchboardViewModel()
        vm.selfMemberID = "me"
        vm.store.selfMemberID = "me"
        let deletedGroupID = vm.workspace.groupOrder[0]
        let survivingGroupID = vm.workspace.groupOrder[1]
        vm.activeGroupID = deletedGroupID

        // A peer deletes that group; the tombstone arrives through the remote-apply path,
        // which deliberately never touches navigation state.
        _ = vm.store.applyRemoteGroupTombstone(
            groupID: deletedGroupID, collectionID: vm.activeCollectionID,
            deletedAt: Date(), by: "someone-else"
        )

        #expect(vm.activeGroup.id == survivingGroupID, "the panel renders the surviving group")
        #expect(vm.activeGroupID == survivingGroupID, "and addresses the same one")

        guard let element = vm.activeGroup.elements.first else {
            Issue.record("seed group has no elements")
            return
        }
        // Asserted as a flip, not as "== true": the seed's first product is already
        // favourited, and a landed toggle turns it off.
        let wasFavorite = element.isFavorite
        vm.toggleFavorite(element.id)
        #expect(vm.selectedElement(id: element.id)?.isFavorite == !wasFavorite, "favourite must land")

        vm.claimOrRelease(element.id)
        #expect(vm.selectedElement(id: element.id)?.claimedBy?.who == "me", "in-use mark must land")

        vm.deleteElement(element.id)
        #expect(vm.selectedElement(id: element.id) == nil, "delete must land")
    }
}

@Suite("Schema designer field keys")
struct FieldKeyTests {

    @Test("Create path dedupes colliding slugs, matching the edit path")
    func createPathDedupesKeys() {
        let raw = [
            NBField(key: "", label: "user id", type: .text),
            NBField(key: "", label: "user-id", type: .secret),
            NBField(key: "", label: "User Id!", type: .text),
        ]
        let fields = GroupFormModel.normalisedFields(raw)
        let keys = fields.map(\.key)
        #expect(keys.count == Set(keys).count, "keys must be unique: \(keys)")
    }

    @Test("Existing fields keep their stable keys through a relabel")
    func editPreservesStableKeys() {
        let original = NBField(key: "password", label: "password", type: .secret)
        let relabelled = NBField(id: original.id, key: original.key, label: "pass phrase", type: .secret)
        let fields = GroupFormModel.normalisedFields([relabelled], existingByID: [original.id: original])
        #expect(fields[0].key == "password")
    }

    @Test("Empty-labelled fields are dropped")
    func emptyLabelsDropped() {
        let raw = [
            NBField(key: "", label: "  ", type: .text),
            NBField(key: "", label: "name", type: .text),
        ]
        #expect(GroupFormModel.normalisedFields(raw).count == 1)
    }

    @Test("saveGroup end to end produces unique keys for colliding labels")
    func saveGroupEndToEnd() {
        let vm = NotchboardViewModel()
        vm.openNewGroup()
        vm.groupForm.name = "collision test"
        vm.groupForm.fields = [
            NBField(key: "", label: "token", type: .secret),
            NBField(key: "", label: "Token!", type: .text),
        ]
        vm.saveGroup()
        guard let group = vm.workspace.groups["collision_test"] else {
            Issue.record("group was not created")
            return
        }
        let keys = group.fields.map(\.key)
        #expect(keys.count == Set(keys).count)
        // The secret definition must not be aliased by its text-typed twin.
        #expect(group.secretFieldKeys.count == 1)
        vm.deleteGroup("collision_test")
    }
}

@Suite("Workspace sanitisation")
struct WorkspaceSanitisationTests {

    @Test("reconcileGroupOrder removes duplicate ids, keeping the first")
    func reconcileRemovesDuplicates() {
        var workspace = MockData.workspace()
        let first = workspace.groupOrder[0]
        workspace.groupOrder.append(first)
        workspace.reconcileGroupOrder()
        #expect(workspace.groupOrder.filter { $0 == first }.count == 1)
    }

    @Test("deduplicateElementIDs remaps later duplicates and keeps the first")
    func deduplicateElementIDs() {
        var workspace = MockData.workspace()
        let sourceGroupID = workspace.groupOrder[0]
        let targetGroupID = workspace.groupOrder[1]
        let duplicated = workspace.groups[sourceGroupID]!.elements[0]
        workspace.groups[targetGroupID]!.elements.append(duplicated)

        workspace.deduplicateElementIDs()

        let allIDs = workspace.groups.values.flatMap { $0.elements.map(\.id) }
        #expect(allIDs.count == Set(allIDs).count, "element ids must be unique after dedupe")
        // First occurrence (in groupOrder order) keeps the original id.
        #expect(workspace.groups[sourceGroupID]?.elements[0].id == duplicated.id)
        #expect(workspace.groups[targetGroupID]?.elements.last?.id != duplicated.id)
        // The remapped copy keeps its content.
        #expect(workspace.groups[targetGroupID]?.elements.last?.name == duplicated.name)
    }

    @Test("restore clamps out-of-range autoReleaseMinutes")
    func restoreClampsAutoRelease() {
        let vm = NotchboardViewModel()
        var state = vm.persistableState(onboardingCompleted: true, onboardingName: "x")
        state.autoReleaseMinutes = 0
        vm.restore(from: state)
        #expect(vm.autoReleaseMinutes == NotchboardViewModel.autoReleaseRange.lowerBound)
        state.autoReleaseMinutes = 100_000
        vm.restore(from: state)
        #expect(vm.autoReleaseMinutes == NotchboardViewModel.autoReleaseRange.upperBound)
    }

    @Test("saveElement rejects the reserved keychain placeholder as a value")
    func placeholderValueRejected() {
        let vm = NotchboardViewModel()
        let countBefore = vm.activeGroup.elements.count
        vm.currentView = .add
        vm.elementForm.name = "sentinel test"
        vm.elementForm.values["username"] = AppStateStore.keychainPlaceholder
        vm.saveElement()
        #expect(vm.activeGroup.elements.count == countBefore)
    }
}

@Suite("SecretsStore round trip", .serialized)
struct SecretsStoreTests {

    @Test("Save, load, delete round-trips a value")
    func roundTrip() {
        let key = "test-\(UUID().uuidString).password"
        // A locked keychain (headless CI) makes save fail — that is exactly the situation
        // the Bool return exists for, so bail out rather than fail the suite.
        guard SecretsStore.save("hunter2", for: key) else { return }
        defer { SecretsStore.delete(for: key) }

        #expect(SecretsStore.load(for: key) == .found("hunter2"))
        SecretsStore.delete(for: key)
        #expect(SecretsStore.load(for: key) == .notFound)
    }

    @Test("pruneOrphans removes unreferenced keys and keeps referenced ones")
    func pruneOrphans() {
        let kept = "test-\(UUID().uuidString).password"
        let orphan = "test-\(UUID().uuidString).password"
        guard SecretsStore.save("keep", for: kept), SecretsStore.save("drop", for: orphan) else { return }
        defer {
            SecretsStore.delete(for: kept)
            SecretsStore.delete(for: orphan)
        }

        // Keep every key currently in the store except the orphan, so entries belonging
        // to the user's real workspace are untouched by this test.
        let valid = Set(SecretsStore.allKeys()).subtracting([orphan])
        SecretsStore.pruneOrphans(keeping: valid)

        #expect(SecretsStore.load(for: kept) == .found("keep"))
        #expect(SecretsStore.load(for: orphan) == .notFound)
    }
}
