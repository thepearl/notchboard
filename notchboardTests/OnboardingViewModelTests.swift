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
