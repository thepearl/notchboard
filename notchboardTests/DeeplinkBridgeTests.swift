//
//  DeeplinkBridgeTests.swift
//  notchboardTests
//
//  Covers the "login on sim" logic with an injected deeplink opener, so no real xcrun
//  process is spawned. The group-switch test is the regression guard for the confirmed
//  bug where the auto-claim silently no-oped if the user changed tabs while simctl ran.
//

import Foundation
import Testing
@testable import notchboard

@Suite("Deeplink scheme validation")
struct DeeplinkSchemeTests {

    @Test("Accepts plausible custom schemes", arguments: ["myapp", "brewly", "my-app.x+y", "a1"])
    func acceptsCustomSchemes(scheme: String) {
        #expect(NotchboardViewModel.isValidDeeplinkScheme(scheme))
    }

    @Test("Rejects network schemes and malformed values", arguments: ["https", "HTTP", "ftp", "file", "1app", "my app", "", "app:colon"])
    func rejectsBadSchemes(scheme: String) {
        #expect(!NotchboardViewModel.isValidDeeplinkScheme(scheme))
    }

    @Test("A pasted universal link never fires the deeplink")
    func universalLinkNeverFires() {
        let vm = NotchboardViewModel()
        vm.deeplinkScheme = "https://app.example.com/login"
        var fired = false
        vm.deeplinkOpener = { _, _ in fired = true }

        guard let element = vm.activeGroup.elements.first(where: { vm.loginUsername(for: $0) != nil }) else {
            Issue.record("seed data has no auth element")
            return
        }
        vm.loginOnSim(element)
        #expect(!fired, "credentials must never be sent through a network scheme")
    }
}

@Suite("Login on sim auto-claim")
struct LoginOnSimTests {

    private func authElement(in vm: NotchboardViewModel) -> NBElement? {
        vm.activeGroup.elements.first { vm.loginUsername(for: $0) != nil && $0.claimedBy == nil }
    }

    @Test("Successful deeplink claims the element in its owning group")
    func successClaims() {
        let vm = NotchboardViewModel()
        vm.deeplinkScheme = "testapp"
        guard let element = authElement(in: vm) else {
            Issue.record("seed data has no free auth element")
            return
        }
        var completion: ((SimctlBridge.Failure?) -> Void)?
        vm.deeplinkOpener = { _, done in completion = done }

        vm.loginOnSim(element)
        completion?(nil)
        #expect(vm.selectedElement(id: element.id)?.claimedBy?.who == vm.selfMemberID)
    }

    @Test("Auto-claim survives a group switch during the simctl round-trip")
    func claimSurvivesGroupSwitch() {
        let vm = NotchboardViewModel()
        vm.deeplinkScheme = "testapp"
        guard let element = authElement(in: vm) else {
            Issue.record("seed data has no free auth element")
            return
        }
        let owningGroupID = vm.activeGroupID
        guard let otherGroupID = vm.workspace.groupOrder.first(where: { $0 != owningGroupID }) else {
            Issue.record("seed data has only one group")
            return
        }

        var completion: ((SimctlBridge.Failure?) -> Void)?
        vm.deeplinkOpener = { _, done in completion = done }

        vm.loginOnSim(element)
        vm.selectGroup(otherGroupID) // user clicks another tab while simctl runs
        completion?(nil)

        let claimed = vm.workspace.groups[owningGroupID]?.elements.first { $0.id == element.id }?.claimedBy
        #expect(claimed?.who == vm.selfMemberID, "the claim must land in the element's owning group")
    }

    @Test("Auto-claim survives a collection switch during the simctl round-trip")
    func claimSurvivesCollectionSwitch() {
        // Phase 2 sibling of the group-switch guard: the owning *collection* is captured at
        // fire time too, or the callback would mutate whatever catalogue is active by then.
        let vm = NotchboardViewModel()
        vm.deeplinkScheme = "testapp"
        guard let element = authElement(in: vm) else {
            Issue.record("seed data has no free auth element")
            return
        }
        let owningCollectionID = vm.activeCollectionID

        var completion: ((SimctlBridge.Failure?) -> Void)?
        vm.deeplinkOpener = { _, done in completion = done }

        vm.loginOnSim(element)
        vm.createCollection(named: "elsewhere") // user switches collections while simctl runs
        completion?(nil)

        let claimed = vm.collections.first { $0.id == owningCollectionID }?
            .workspace.groups.values.flatMap(\.elements)
            .first { $0.id == element.id }?.claimedBy
        #expect(claimed?.who == vm.selfMemberID, "the claim must land in the element's owning collection")
        #expect(vm.workspace.elementCount == 0, "the active (new) collection must stay untouched")
    }

    @Test("Failed deeplink leaves the element unclaimed")
    func failureDoesNotClaim() {
        let vm = NotchboardViewModel()
        vm.deeplinkScheme = "testapp"
        guard let element = authElement(in: vm) else {
            Issue.record("seed data has no free auth element")
            return
        }
        var completion: ((SimctlBridge.Failure?) -> Void)?
        vm.deeplinkOpener = { _, done in completion = done }

        vm.loginOnSim(element)
        completion?(.noBootedSimulator)
        #expect(vm.selectedElement(id: element.id)?.claimedBy == nil)
    }

    @Test("The fired URL carries the username and encodes the password")
    func urlCarriesCredentials() {
        let vm = NotchboardViewModel()
        vm.deeplinkScheme = "testapp"
        guard let element = vm.activeGroup.elements.first(where: {
            vm.loginUsername(for: $0) != nil && vm.loginPassword(for: $0) != nil
        }) else {
            Issue.record("seed data has no full auth element")
            return
        }
        var firedURL: String?
        vm.deeplinkOpener = { url, _ in firedURL = url }

        vm.loginOnSim(element)
        guard let firedURL else {
            Issue.record("deeplink was not fired")
            return
        }
        #expect(firedURL.hasPrefix("testapp://debug/login?user="))
        #expect(firedURL.contains("&pass="))
    }
}
