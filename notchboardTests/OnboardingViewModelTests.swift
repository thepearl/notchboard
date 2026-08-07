//
//  OnboardingViewModelTests.swift
//  notchboardTests
//
//  Covers the onboarding step machine and the accessibility poll loop. The poll test
//  is the regression guard for a real bug: a cancelled `Task.sleep` swallowed by `try?`
//  turned the loop into a 100% CPU main-actor spin after leaving step 4.
//

import Foundation
import Testing
@testable import notchboard

@Suite("Onboarding flow")
struct OnboardingFlowTests {

    @Test("Step 2 requires a name")
    func step2RequiresName() {
        let vm = OnboardingViewModel()
        vm.step = 2
        vm.name = "   "
        guard case .error = vm.advance() else {
            Issue.record("expected an error for an empty name")
            return
        }
        vm.name = "Nadia Benali"
        guard case .advanced = vm.advance() else {
            Issue.record("expected to advance with a valid name")
            return
        }
        #expect(vm.step == 3)
    }

    @Test("Step 4 requires accessibility before finishing")
    func step4RequiresAccessibility() {
        let vm = OnboardingViewModel()
        vm.step = 4
        vm.accessibilityGranted = false
        guard case .error = vm.advance() else {
            Issue.record("expected an error without accessibility")
            return
        }
        vm.accessibilityGranted = true
        guard case .finished = vm.advance() else {
            Issue.record("expected to finish once granted")
            return
        }
    }

    @Test("Back never goes below step 1")
    func backClampsAtOne() {
        let vm = OnboardingViewModel()
        vm.back()
        #expect(vm.step == 1)
    }

    @Test("Step 3 advances without an invite code")
    func step3NeverGates() {
        // The regression this guards: step 3 used to demand a code of six or more characters,
        // making a team a hard prerequisite. Nothing about being solo may block onboarding.
        let vm = OnboardingViewModel()
        vm.step = 3
        guard case .advanced = vm.advance() else {
            Issue.record("step 3 must not gate — a solo user has no invite code")
            return
        }
        #expect(vm.step == 4)
    }

    @Test("Sample is the default starting point")
    func defaultsToSample() {
        #expect(OnboardingViewModel().startingPoint == .sample)
    }

    @Test("reset() restores the default starting point")
    func resetClearsStartingPoint() {
        let vm = OnboardingViewModel()
        vm.startingPoint = .empty
        vm.reset()
        #expect(vm.startingPoint == .sample)
        #expect(vm.step == 1)
    }

    @Test("Every starting point carries its own copy", arguments: NBStartingPoint.allCases)
    func startingPointCopyIsComplete(option: NBStartingPoint) {
        #expect(!option.title.isEmpty)
        #expect(!option.detail.isEmpty)
        #expect(!option.ctaLabel.isEmpty)
        #expect(!option.glyph.isEmpty)
    }
}

@Suite("Seeding a first catalogue")
struct StartingPointSeedingTests {

    @Test("The empty starting point gives you one group to type into, not a dead panel")
    func emptyIsUsable() {
        let workspace = MockData.emptyWorkspace()
        #expect(workspace.groupOrder.count == 1)
        #expect(workspace.groups["users"]?.elements.isEmpty == true)
        #expect(workspace.groups["users"]?.fields.isEmpty == false, "a group with no fields can't hold anything")
    }

    @Test("Seeding keeps sample secrets, unlike importing an untrusted file")
    func seedingPreservesSecrets() {
        let vm = NotchboardViewModel()
        vm.adoptSeedWorkspace(MockData.workspace())
        let passwords = vm.workspace.groups["users"]?.elements.compactMap { $0.values["password"] } ?? []
        #expect(passwords.contains { !$0.isEmpty }, "sample passwords are the point of the sample")
    }

    @Test("Importing still blanks secrets, whatever the file claims")
    func importBlanksSecrets() {
        let vm = NotchboardViewModel()
        var hostile = MockData.workspace()
        // A hand-crafted file carrying credentials must not inject them.
        if var group = hostile.groups["users"], !group.elements.isEmpty {
            group.elements[0].values["password"] = "smuggled-in"
            hostile.groups["users"] = group
        }
        vm.replaceWorkspace(with: hostile)
        let smuggled = vm.workspace.groups["users"]?.elements.compactMap { $0.values["password"] } ?? []
        #expect(!smuggled.contains("smuggled-in"))
    }

    @Test("The demo catalogue keeps the teammates, so the concept can still be shown")
    func demoKeepsTheTeam() {
        let demo = MockData.demoWorkspace()
        #expect(!demo.members.isEmpty)
        let foreign = demo.groups.values.flatMap(\.elements).compactMap(\.claimedBy).filter { $0.who != "you" }
        #expect(!foreign.isEmpty)
    }
}

@Suite("Accessibility poll loop")
struct AccessibilityPollTests {

    @Test("Poll exits promptly when its task is cancelled")
    func pollExitsOnCancellation() async {
        let vm = OnboardingViewModel()
        let poll = Task {
            await vm.pollAccessibility(probe: { false }, interval: .milliseconds(20))
            return true
        }
        try? await Task.sleep(for: .milliseconds(60))
        poll.cancel()

        // Race the poll against a generous timeout: with the old bug the poll never
        // returned after cancellation, so this guards the fix without hanging CI.
        let finishedInTime = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await poll.value }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        #expect(finishedInTime, "poll loop did not exit after cancellation")
    }

    @Test("Poll stops once the probe reports granted")
    func pollStopsWhenGranted() async {
        let vm = OnboardingViewModel()
        await vm.pollAccessibility(probe: { true }, interval: .milliseconds(1))
        #expect(vm.accessibilityGranted)
    }
}
