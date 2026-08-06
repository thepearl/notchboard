//
//  UXBehaviourTests.swift
//  notchboardTests
//
//  Covers the coach-mark deferral round trip and the claim-tooltip grace period —
//  both fixes for audited UX dead ends.
//

import Foundation
import Testing
@testable import notchboard

@Suite("Coach mark deferral")
struct CoachMarkDeferralTests {

    @Test("pendingCoachMark round-trips through persisted state")
    func pendingCoachMarkPersists() {
        let vm = NotchboardViewModel()
        vm.pendingCoachMark = true
        let state = vm.persistableState(onboardingCompleted: true, onboardingName: "n")
        #expect(state.coachMarkPending)

        let fresh = NotchboardViewModel()
        fresh.restore(from: state)
        #expect(fresh.pendingCoachMark)
    }

    @Test("Opening the panel yourself cancels the pending coach mark")
    func togglingExpandCancelsPending() {
        let vm = NotchboardViewModel()
        vm.pendingCoachMark = true
        vm.toggleExpanded()
        #expect(!vm.pendingCoachMark)
        #expect(!vm.showCoachMark)
    }

    @Test("Old state files without the field decode with pending false")
    func lenientDecode() throws {
        let vm = NotchboardViewModel()
        var state = vm.persistableState(onboardingCompleted: true, onboardingName: "n")
        state.coachMarkPending = true
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        json.removeValue(forKey: "coachMarkPending")
        let decoded = try JSONDecoder().decode(PersistedAppState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(!decoded.coachMarkPending)
    }
}

@Suite("Claim tooltip grace period")
struct ClaimTooltipTests {

    @Test("Scheduled dismissal happens after the grace period")
    func scheduledDismissalFires() async {
        let vm = NotchboardViewModel()
        vm.showClaimTooltip("e1")
        vm.scheduleClaimTooltipDismissal()
        #expect(vm.tooltipElementID == "e1", "tooltip must survive the instant of leaving the badge")
        try? await Task.sleep(for: .milliseconds(600))
        #expect(vm.tooltipElementID == nil, "tooltip must dismiss after the grace period")
    }

    @Test("Entering the popover cancels the pending dismissal")
    func cancelKeepsTooltip() async {
        let vm = NotchboardViewModel()
        vm.showClaimTooltip("e1")
        vm.scheduleClaimTooltipDismissal()
        vm.cancelClaimTooltipDismissal()
        try? await Task.sleep(for: .milliseconds(600))
        #expect(vm.tooltipElementID == "e1", "cancelled dismissal must leave the tooltip up")
    }

    @Test("Explicit dismissal is immediate")
    func explicitDismiss() {
        let vm = NotchboardViewModel()
        vm.showClaimTooltip("e1")
        vm.dismissClaimTooltip()
        #expect(vm.tooltipElementID == nil)
    }
}
