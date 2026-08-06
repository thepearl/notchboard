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
        #expect(vm.selectedElement(id: free.id)?.claimedBy?.who == "you")
        vm.claimOrRelease(free.id)
        #expect(vm.selectedElement(id: free.id)?.claimedBy == nil)
    }

    @Test("Claiming someone else's element is refused")
    func claimingForeignElementRefused() {
        let vm = NotchboardViewModel()
        guard let foreign = vm.activeGroup.elements.first(where: { ($0.claimedBy?.who ?? "you") != "you" }) else {
            Issue.record("seed data has no foreign claim")
            return
        }
        let before = vm.selectedElement(id: foreign.id)?.claimedBy
        vm.claimOrRelease(foreign.id)
        #expect(vm.selectedElement(id: foreign.id)?.claimedBy == before)
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
        vm.addName = "   "
        vm.saveElement()
        #expect(vm.activeGroup.elements.count == countBefore)
    }

    @Test("Repeated openAdd preserves an in-progress draft")
    func openAddPreservesDraft() {
        let vm = NotchboardViewModel()
        vm.openAdd()
        vm.addName = "half-typed draft"
        vm.addValues["username"] = "draft-user"
        vm.openAdd() // a repeated ⌘N must not wipe the form
        #expect(vm.addName == "half-typed draft")
        #expect(vm.addValues["username"] == "draft-user")
    }

    @Test("openAdd after an edit starts clean, never leaking the edited values")
    func openAddAfterEditIsClean() {
        let vm = NotchboardViewModel()
        let element = vm.activeGroup.elements[0]
        vm.openEdit(element)
        #expect(vm.addName == element.name)
        vm.openAdd()
        #expect(vm.editingElementID == nil)
        #expect(vm.addName.isEmpty)
        #expect(vm.addValues.isEmpty)
    }

    @Test("saveElement appends a new element to the active group")
    func saveElementCreates() {
        let vm = NotchboardViewModel()
        let countBefore = vm.activeGroup.elements.count
        vm.openAdd()
        vm.addName = "test element"
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
        let future = NBClaim(who: "you", claimedAt: Date().addingTimeInterval(3600))
        #expect(future.minutesAgo == 0)
    }
}

@Suite("Claim age label")
struct ClaimAgeLabelTests {

    private func claim(minutesAgo: Int) -> NBClaim {
        NBClaim(who: "you", minutesAgo: minutesAgo)
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
