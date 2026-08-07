//
//  FieldAndEnvironmentTests.swift
//  notchboardTests
//
//  The two rules added on 2026-08-07: an element can live in several environments at once,
//  and a field's declared type actually constrains its value. Both are enforced in the
//  model layer rather than only in the form, because values also arrive from imports and
//  hand-edited files — the tests below go through that same layer.
//

import Foundation
import Testing
@testable import notchboard

@Suite("Field type enforcement")
struct FieldValidationTests {

    private func field(_ type: NBFieldType, options: [String] = []) -> NBField {
        NBField(key: "f", label: "field", type: type, options: options)
    }

    @Test("Empty is always allowed — not filled in isn't invalid", arguments: NBFieldType.allCases)
    func emptyAllowed(type: NBFieldType) {
        #expect(NBFieldValidation.problem(with: "", for: field(type)) == nil)
    }

    @Test("Text and secret accept anything", arguments: [NBFieldType.text, .secret])
    func freeTypes(type: NBFieldType) {
        #expect(NBFieldValidation.problem(with: "¯\\_(ツ)_/¯", for: field(type)) == nil)
    }

    @Test("Numbers must parse", arguments: ["18.50", "-3", "0"])
    func numbersAccepted(value: String) {
        #expect(NBFieldValidation.problem(with: value, for: field(.number)) == nil)
    }

    @Test("Non-numbers are refused", arguments: ["18,50", "eighteen", "1.2.3", "12px"])
    func numbersRefused(value: String) {
        #expect(NBFieldValidation.problem(with: value, for: field(.number)) != nil)
    }

    @Test("Bools are true or false, case-insensitively", arguments: ["true", "false", "TRUE"])
    func boolsAccepted(value: String) {
        #expect(NBFieldValidation.problem(with: value, for: field(.bool)) == nil)
    }

    @Test("Bool lookalikes are refused", arguments: ["yes", "1", "oui"])
    func boolsRefused(value: String) {
        #expect(NBFieldValidation.problem(with: value, for: field(.bool)) != nil)
    }

    @Test("URLs need a scheme and a host", arguments: ["https://api.acme.dev", "notchdemo://debug/login", "http://localhost:8080/v2"])
    func urlsAccepted(value: String) {
        #expect(NBFieldValidation.problem(with: value, for: field(.url)) == nil)
    }

    @Test("Bare hosts and half-typed URLs are refused", arguments: ["api.acme.dev", "https://", "https://acme dev", "just words"])
    func urlsRefused(value: String) {
        #expect(NBFieldValidation.problem(with: value, for: field(.url)) != nil)
    }

    @Test("Dates are ISO and real", arguments: ["2026-12-31", "2026-02-28"])
    func datesAccepted(value: String) {
        #expect(NBFieldValidation.problem(with: value, for: field(.date)) == nil)
    }

    @Test("Other formats and impossible dates are refused", arguments: ["31/12/2026", "2026-13-01", "2026-02-30", "tomorrow"])
    func datesRefused(value: String) {
        // Locale-independent on purpose: these values travel between machines, so the same
        // file must not be valid on one Mac and invalid on another.
        #expect(NBFieldValidation.problem(with: value, for: field(.date)) != nil)
    }

    @Test("A picker with options only accepts one of them")
    func pickerConstrained() {
        let tier = field(.picker, options: ["core", "premium"])
        #expect(NBFieldValidation.problem(with: "core", for: tier) == nil)
        #expect(NBFieldValidation.problem(with: "gold", for: tier) != nil)
    }

    @Test("A picker with no options falls back to free text")
    func pickerWithoutOptions() {
        #expect(NBFieldValidation.problem(with: "anything", for: field(.picker)) == nil)
    }

    @Test("firstProblem names the offending field")
    func problemNamesField() {
        let fields = [NBField(key: "price", label: "price", type: .number)]
        let problem = NBFieldValidation.firstProblem(in: ["price": "free"], fields: fields)
        #expect(problem?.contains("price") == true)
    }

    @Test("Number input filtering keeps a typeable value")
    func numberFiltering() {
        #expect(NBFieldValidation.filtered("1a2b3", for: .number) == "123")
        #expect(NBFieldValidation.filtered("18.50", for: .number) == "18.50")
        #expect(NBFieldValidation.filtered("1.2.3", for: .number) == "1.23", "only the first separator survives")
        #expect(NBFieldValidation.filtered("-5", for: .number) == "-5")
        #expect(NBFieldValidation.filtered("5-5", for: .number) == "55", "a sign is only allowed to lead")
        #expect(NBFieldValidation.filtered("anything", for: .text) == "anything", "only numbers are filtered")
    }

    @Test("saveElement refuses a value that contradicts its field type")
    func saveBlocksInvalidValue() {
        let vm = NotchboardViewModel()
        vm.selectGroup("products") // has a number field (price) and a picker (tier)
        let before = vm.activeGroup.elements.count
        vm.openAdd()
        vm.elementForm.name = "bad price"
        vm.elementForm.values["price"] = "free"
        vm.saveElement()
        #expect(vm.activeGroup.elements.count == before, "an unparseable number must not reach the catalogue")
    }
}

@Suite("Multi-environment elements")
struct EnvironmentTests {

    @Test("An element can hold several environments and reads them in order")
    func sortedEnvironments() {
        let element = NBElement(
            id: "e", name: "n", environments: [.prd, .dev, .stg], isFavorite: false,
            claimedBy: nil, note: "", lastUsed: "", values: [:]
        )
        #expect(element.sortedEnvironments == [.dev, .stg, .prd])
    }

    @Test("The filter matches any environment the element lives in")
    func filterMatchesAny() {
        let vm = NotchboardViewModel()
        vm.selectGroup("users")
        guard let multi = vm.activeGroup.elements.first(where: { $0.environments.count > 1 }) else {
            Issue.record("the sample catalogue should ship a multi-environment element")
            return
        }
        for env in multi.environments {
            vm.environmentFilter = env
            #expect(vm.filteredElements.contains { $0.id == multi.id }, "\(env.rawValue) must find it")
        }
        vm.environmentFilter = .all
        #expect(vm.filteredElements.contains { $0.id == multi.id })
    }

    @Test("Toggling adds and removes, but never leaves an element homeless")
    func toggleKeepsAtLeastOne() {
        let vm = NotchboardViewModel()
        vm.openAdd()
        #expect(vm.elementForm.environments == [.dev])
        vm.toggleAddEnvironment(.stg)
        #expect(vm.elementForm.environments == [.dev, .stg])
        vm.toggleAddEnvironment(.dev)
        #expect(vm.elementForm.environments == [.stg])
        vm.toggleAddEnvironment(.stg)
        #expect(vm.elementForm.environments == [.stg], "removing the last environment is refused")
    }

    @Test("`.all` is a filter sentinel and can never be assigned")
    func allIsNotAssignable() {
        #expect(!NBEnvironment.assignable.contains(.all))
        let vm = NotchboardViewModel()
        vm.openAdd()
        vm.toggleAddEnvironment(.all)
        #expect(!vm.elementForm.environments.contains(.all))
    }

    @Test("Saving writes every selected environment")
    func saveKeepsAllEnvironments() {
        let vm = NotchboardViewModel()
        vm.openAdd()
        vm.elementForm.name = "multi"
        vm.toggleAddEnvironment(.stg)
        vm.saveElement()
        #expect(vm.activeGroup.elements.last?.environments == [.dev, .stg])
    }

    @Test("Editing an element preserves its environments")
    func editPreservesEnvironments() {
        let vm = NotchboardViewModel()
        guard let element = vm.activeGroup.elements.first(where: { $0.environments.count > 1 }) else {
            Issue.record("no multi-environment element in the sample")
            return
        }
        vm.openEdit(element)
        #expect(vm.elementForm.environments == element.environments)
        vm.saveElement()
        #expect(vm.selectedElement(id: element.id)?.environments == element.environments)
    }
}

@Suite("Production mixing warning")
struct ProductionMixWarningTests {

    @Test("Warns when production would join another environment")
    func warnsOnMix() {
        let vm = NotchboardViewModel()
        vm.openAdd() // [.dev]
        #expect(vm.productionMixWarningNeeded(togglingOn: .prd))
    }

    @Test("Production alone is not a mix")
    func prdAloneIsFine() {
        let vm = NotchboardViewModel()
        vm.openAdd()
        vm.elementForm.environments = [.prd]
        #expect(!vm.productionMixWarningNeeded(togglingOn: .prd), "removing prd can't create a mix")
        vm.elementForm.environments = []
        #expect(!vm.productionMixWarningNeeded(togglingOn: .prd), "prd on its own needs no warning")
    }

    @Test("Adding a second environment to a production element also warns")
    func warnsFromTheOtherDirection() {
        let vm = NotchboardViewModel()
        vm.openAdd()
        vm.elementForm.environments = [.prd]
        #expect(vm.productionMixWarningNeeded(togglingOn: .stg))
    }

    @Test("Never warns for dev and staging together")
    func noWarningWithoutProduction() {
        let vm = NotchboardViewModel()
        vm.openAdd()
        #expect(!vm.productionMixWarningNeeded(togglingOn: .stg))
    }

    @Test("Suppressing silences it, and the choice survives a persist/restore round trip")
    func suppressionPersists() {
        let vm = NotchboardViewModel()
        vm.openAdd()
        vm.suppressProductionMixWarning = true
        #expect(!vm.productionMixWarningNeeded(togglingOn: .prd))

        let state = vm.persistableState(onboardingCompleted: true, onboardingName: "x")
        let restored = NotchboardViewModel()
        restored.restore(from: state)
        #expect(restored.suppressProductionMixWarning, "a warning dismissed for good must stay dismissed")
    }

    @Test("The model knows which elements mix production")
    func modelFlagsMix() {
        func element(_ envs: Set<NBEnvironment>) -> NBElement {
            NBElement(id: "e", name: "n", environments: envs, isFavorite: false,
                      claimedBy: nil, note: "", lastUsed: "", values: [:])
        }
        #expect(element([.prd, .dev]).mixesProductionWithOthers)
        #expect(!element([.prd]).mixesProductionWithOthers)
        #expect(!element([.dev, .stg]).mixesProductionWithOthers)
    }
}

@Suite("Deeplink scheme entry")
struct DeeplinkSchemeEntryTests {

    @Test("A valid scheme is normalised and stored on the active collection")
    func storesNormalised() {
        let vm = NotchboardViewModel()
        vm.setDeeplinkScheme("notchdemo://")
        #expect(vm.deeplinkScheme == "notchdemo")
    }

    @Test("A network scheme is refused rather than stored")
    func refusesNetworkScheme() {
        let vm = NotchboardViewModel()
        vm.setDeeplinkScheme("https://app.acme.dev")
        #expect(vm.deeplinkScheme.isEmpty, "credentials must never be fireable at a real host")
    }

    @Test("Clearing is allowed and turns the button off")
    func clearing() {
        let vm = NotchboardViewModel()
        vm.setDeeplinkScheme("notchdemo")
        vm.setDeeplinkScheme("  ")
        #expect(vm.deeplinkScheme.isEmpty)
    }

    @Test("The scheme belongs to its collection, not the app")
    func perCollection() {
        let vm = NotchboardViewModel()
        let first = vm.activeCollectionID
        vm.setDeeplinkScheme("notchdemo")
        vm.createCollection(named: "other")
        vm.setDeeplinkScheme("brewly")
        vm.switchCollection(first)
        #expect(vm.deeplinkScheme == "notchdemo")
    }
}
