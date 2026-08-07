//
//  NotchboardViewModelTests.swift
//  notchboardTests
//
//  Behavioural tests for the catalogue view model — navigation, filtering, claims,
//  and the CRUD paths. Runs inside the app via TEST_HOST; AppDelegate skips its
//  runtime setup (panel, timers, persistence) when it detects the test environment,
//  so these tests never touch the user's real state.json or Keychain entries other
//  than the throwaway keys they create themselves.
//

import Foundation
import Testing
@testable import notchboard

@Suite("NotchboardViewModel basics")
struct NotchboardViewModelBasicsTests {

    @Test("Seed workspace loads with a valid active group")
    func seedWorkspaceIsSane() {
        let vm = NotchboardViewModel()
        #expect(!vm.workspace.groupOrder.isEmpty)
        #expect(vm.workspace.groups[vm.activeGroupID] != nil)
        #expect(!vm.activeGroup.fields.isEmpty)
    }

    @Test("Search filters across name, note, and field values")
    func searchFiltersAcrossFields() {
        let vm = NotchboardViewModel()
        let first = vm.activeGroup.elements[0]
        vm.searchText = first.name
        #expect(vm.filteredElements.contains { $0.id == first.id })
        vm.searchText = "definitely-not-a-real-element-zzz"
        #expect(vm.filteredElements.isEmpty)
    }

    @Test("Claiming a free element records it as yours; releasing frees it")
    func claimAndRelease() {
        let vm = NotchboardViewModel()
        guard let free = vm.activeGroup.elements.first(where: { $0.claimedBy == nil }) else {
            Issue.record("seed data has no free element to claim")
            return
        }
        vm.claimOrRelease(free.id)
        #expect(vm.selectedElement(id: free.id)?.claimedBy?.who == vm.selfMemberID, "claims are attributed to the stable member id, not the literal \"you\"")
        vm.claimOrRelease(free.id)
        #expect(vm.selectedElement(id: free.id)?.claimedBy == nil)
    }

    @Test("Claiming someone else's element is refused")
    func claimingForeignElementRefused() {
        // The foreign claim is constructed here rather than taken from seed data: the sample
        // catalogue ships with no claims at all now (a solo user shouldn't open the app to
        // rows locked by people who don't exist), and building it in-test isolates this case
        // from whatever the seed happens to contain.
        let vm = NotchboardViewModel()
        guard let target = vm.activeGroup.elements.first else {
            Issue.record("seed data has no elements")
            return
        }
        var group = vm.activeGroup
        let index = group.elements.firstIndex { $0.id == target.id }!
        group.elements[index].claimedBy = NBClaim(who: "someone-else", minutesAgo: 5)
        vm.workspace.groups[vm.activeGroupID] = group

        let before = vm.selectedElement(id: target.id)?.claimedBy
        vm.claimOrRelease(target.id)
        #expect(vm.selectedElement(id: target.id)?.claimedBy == before, "a foreign claim must not be released")
    }

    @Test("The sample catalogue ships with no claims at all to strand a solo user")
    func sampleHasNoForeignClaims() {
        let workspace = MockData.workspace()
        let claims = workspace.groups.values
            .flatMap(\.elements)
            .compactMap(\.claimedBy)
        #expect(claims.isEmpty, "seed claims by absent owners can never be released")
        #expect(workspace.members.isEmpty)
    }

    @Test("Restoring frees claims held by someone absent from the catalogue")
    func restoreFreesOrphanedClaims() {
        // Real scenario: a catalogue seeded before the fake teammates were removed keeps
        // rows claimed by tom/sara/mia. Those can never be released through the UI, so the
        // rows stay locked and the notch badge over-counts forever.
        let vm = NotchboardViewModel()
        var workspace = MockData.demoWorkspace()
        workspace.members = [:] // the claimants are gone, the claims remain
        let orphanedBefore = workspace.groups.values.flatMap(\.elements).filter { $0.claimedBy != nil }.count
        #expect(orphanedBefore > 0)

        var state = vm.persistableState(onboardingCompleted: true, onboardingName: "x")
        state.workspace = workspace
        vm.restore(from: state)

        let stillClaimed = vm.workspace.groups.values.flatMap(\.elements).compactMap(\.claimedBy)
        #expect(stillClaimed.isEmpty, "an unreleasable claim must not survive a load")
    }

    @Test("Taking over a foreign claim is the way off a permanently locked row")
    func takeOverFreesALockedRow() {
        // Without a backend the claimant can never release it, so before this existed the
        // only escape was deleting the element.
        let vm = NotchboardViewModel()
        guard let target = vm.activeGroup.elements.first else {
            Issue.record("seed data has no elements")
            return
        }
        var group = vm.activeGroup
        let index = group.elements.firstIndex { $0.id == target.id }!
        group.elements[index].claimedBy = NBClaim(who: "someone-else", minutesAgo: 30)
        vm.workspace.groups[vm.activeGroupID] = group

        vm.takeOver(target.id)
        #expect(vm.selectedElement(id: target.id)?.claimedBy.map(vm.isMine) == true)
    }

    @Test("Taking over does nothing to your own claim or a free element")
    func takeOverIsANoOpOtherwise() {
        let vm = NotchboardViewModel()
        guard let free = vm.activeGroup.elements.first(where: { $0.claimedBy == nil }) else {
            Issue.record("seed data has no free element")
            return
        }
        vm.takeOver(free.id)
        #expect(vm.selectedElement(id: free.id)?.claimedBy == nil, "a free element shouldn't be claimed by a takeover")
    }

    @Test("isSolo reflects whether the catalogue has other members")
    func isSoloTracksMembers() {
        let vm = NotchboardViewModel()
        #expect(vm.isSolo, "the sample catalogue ships with no teammates")
        vm.workspace.members = MockData.demoMembers
        #expect(!vm.isSolo)
    }

    @Test("Restoring keeps claims whose claimant is a real member")
    func restoreKeepsValidClaims() {
        let vm = NotchboardViewModel()
        var state = vm.persistableState(onboardingCompleted: true, onboardingName: "x")
        state.workspace = MockData.demoWorkspace() // members present, claims valid
        vm.restore(from: state)

        let claims = vm.workspace.groups.values.flatMap(\.elements).compactMap(\.claimedBy)
        #expect(!claims.isEmpty, "claims by real members are legitimate and must survive")
    }

    @Test("Your own claims always survive a load")
    func restoreKeepsOwnClaims() {
        let vm = NotchboardViewModel()
        var workspace = MockData.workspace()
        if var group = workspace.groups["users"], !group.elements.isEmpty {
            group.elements[0].claimedBy = NBClaim(who: vm.selfMemberID, minutesAgo: 2)
            workspace.groups["users"] = group
        }
        var state = vm.persistableState(onboardingCompleted: true, onboardingName: "x")
        state.workspace = workspace
        vm.restore(from: state)

        let mine = vm.workspace.groups.values.flatMap(\.elements).compactMap(\.claimedBy).filter { vm.isMine($0) }
        #expect(mine.count == 1)
    }

    @Test("Sample element ids are unique, so two catalogues can't collide in the Keychain")
    func sampleElementIDsAreUnique() {
        let ids = MockData.workspace().groups.values.flatMap { $0.elements.map(\.id) }
        #expect(ids.count == Set(ids).count)
        // Short ids like "u1" collided across catalogues, since Keychain account keys are
        // "<elementID>.<fieldKey>" with no collection component.
        #expect(ids.allSatisfy { $0.count > 8 })
    }

    @Test("Keyboard selection clamps at both ends of the filtered list")
    func keyboardSelectionClamps() {
        let vm = NotchboardViewModel()
        let elements = vm.filteredElements
        guard elements.count >= 2 else {
            Issue.record("seed data too small for keyboard navigation test")
            return
        }
        vm.moveKeyboardSelection(1)
        #expect(vm.keyboardSelectionID == elements[0].id)
        vm.moveKeyboardSelection(-1)
        #expect(vm.keyboardSelectionID == elements[0].id)
        for _ in 0..<(elements.count + 5) { vm.moveKeyboardSelection(1) }
        #expect(vm.keyboardSelectionID == elements[elements.count - 1].id)
    }

    @Test("saveElement refuses an empty name")
    func saveElementValidatesName() {
        let vm = NotchboardViewModel()
        let countBefore = vm.activeGroup.elements.count
        vm.openAdd()
        vm.elementForm.name = "   "
        vm.saveElement()
        #expect(vm.activeGroup.elements.count == countBefore)
    }

    @Test("Repeated openAdd preserves an in-progress draft")
    func openAddPreservesDraft() {
        let vm = NotchboardViewModel()
        vm.openAdd()
        vm.elementForm.name = "half-typed draft"
        vm.elementForm.values["username"] = "draft-user"
        vm.openAdd() // a repeated ⌘N must not wipe the form
        #expect(vm.elementForm.name == "half-typed draft")
        #expect(vm.elementForm.values["username"] == "draft-user")
    }

    @Test("openAdd after an edit starts clean, never leaking the edited values")
    func openAddAfterEditIsClean() {
        let vm = NotchboardViewModel()
        let element = vm.activeGroup.elements[0]
        vm.openEdit(element)
        #expect(vm.elementForm.name == element.name)
        vm.openAdd()
        #expect(vm.elementForm.editingElementID == nil)
        #expect(vm.elementForm.name.isEmpty)
        #expect(vm.elementForm.values.isEmpty)
    }

    @Test("saveElement appends a new element to the active group")
    func saveElementCreates() {
        let vm = NotchboardViewModel()
        let countBefore = vm.activeGroup.elements.count
        vm.openAdd()
        vm.elementForm.name = "test element"
        vm.saveElement()
        #expect(vm.activeGroup.elements.count == countBefore + 1)
        #expect(vm.activeGroup.elements.last?.name == "test element")
    }
}

@Suite("Workspace model")
struct WorkspaceModelTests {

    @Test("reconcileGroupOrder drops missing ids and appends unordered groups")
    func reconcileGroupOrder() {
        var workspace = MockData.workspace()
        workspace.groupOrder.append("ghost-group")
        let known = workspace.groupOrder.filter { $0 != "ghost-group" }
        workspace.groupOrder = [known[0]]
        workspace.reconcileGroupOrder()
        #expect(!workspace.groupOrder.contains("ghost-group"))
        #expect(Set(workspace.groupOrder) == Set(workspace.groups.keys))
    }

    @Test("Claim ages never go negative")
    func claimAgeClamped() {
        let future = NBClaim(who: "m1", claimedAt: Date().addingTimeInterval(3600))
        #expect(future.minutesAgo == 0)
    }
}

@Suite("Claim age label")
struct ClaimAgeLabelTests {

    private func claim(minutesAgo: Int) -> NBClaim {
        NBClaim(who: "m1", minutesAgo: minutesAgo)
    }

    @Test("Fresh claims read as just now")
    func justNow() {
        #expect(claim(minutesAgo: 0).ageLabel == "just now")
    }

    @Test("Under an hour reads in minutes")
    func minutes() {
        #expect(claim(minutesAgo: 1).ageLabel == "1 min ago")
        #expect(claim(minutesAgo: 42).ageLabel == "42 min ago")
        #expect(claim(minutesAgo: 59).ageLabel == "59 min ago")
    }

    @Test("An hour and beyond rolls up to hours")
    func hours() {
        #expect(claim(minutesAgo: 60).ageLabel == "1 hr ago")
        #expect(claim(minutesAgo: 200).ageLabel == "3 hr ago")
        #expect(claim(minutesAgo: 60 * 23).ageLabel == "23 hr ago")
    }

    @Test("A day and beyond rolls up to days")
    func days() {
        #expect(claim(minutesAgo: 60 * 24).ageLabel == "1 day ago")
        #expect(claim(minutesAgo: 60 * 24 * 15).ageLabel == "15 days ago")
    }

    @Test("Long-lived claims never render a grouping separator")
    func noThousandsSeparator() {
        // The bug this replaced: a claim left overnight rendered as "claimed 22,028m ago",
        // because SwiftUI's Text interpolation of an Int applies number grouping.
        for minutes in [1_000, 22_028, 100_000] {
            let label = claim(minutesAgo: minutes).ageLabel
            #expect(!label.contains(","), "unexpected separator in “\(label)”")
            #expect(!label.contains("\u{202F}"), "unexpected narrow space in “\(label)”")
        }
    }
}
