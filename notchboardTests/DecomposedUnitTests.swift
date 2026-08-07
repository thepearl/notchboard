//
//  DecomposedUnitTests.swift
//  notchboardTests
//
//  Direct coverage for the types split out of NotchboardViewModel on 2026-08-07. The
//  behaviour they own was already tested through the view model; these exercise each seam
//  on its own, which is the point of having them — CollectionStore in particular is what
//  the eventual sync milestone will drive without a panel attached.
//

import Foundation
import Testing
@testable import notchboard

@Suite("CollectionStore")
struct CollectionStoreTests {

    @Test("Starts with exactly one seeded collection, active")
    func seedsOne() {
        let store = CollectionStore()
        #expect(store.collections.count == 1)
        #expect(store.activeCollectionID == store.collections[0].id)
        #expect(!store.workspace.groups.isEmpty)
    }

    @Test("An empty list is refused at construction — the panel has no zero-collection state")
    func neverEmpty() {
        #expect(CollectionStore(collections: []).collections.count == 1)
    }

    @Test("A stale active id resolves to the first collection instead of trapping")
    func staleActiveIDDegrades() {
        let store = CollectionStore()
        store.activeCollectionID = "ghost"
        #expect(store.active.id == store.collections[0].id)
        #expect(!store.workspace.name.isEmpty)
    }

    @Test("workspace is a real facade: writes land in the active collection")
    func workspaceFacadeWrites() {
        let store = CollectionStore()
        store.workspace.name = "renamed"
        #expect(store.collections[0].workspace.name == "renamed")
    }

    @Test("Fully-addressed mutation ignores whatever is active now")
    func addressedMutation() {
        let store = CollectionStore()
        let firstID = store.activeCollectionID
        let groupID = store.workspace.groupOrder[0]
        let elementID = store.workspace.groups[groupID]!.elements[0].id
        store.create(named: "elsewhere") // active moves away

        store.mutate(elementID, group: groupID, collection: firstID) { $0.isFavorite = true }
        #expect(store.element(elementID, group: groupID, collection: firstID)?.isFavorite == true)
        #expect(store.active.workspace.elementCount == 0, "the now-active collection is untouched")
    }

    @Test("Duplicating never shares element ids with its source")
    func duplicateRemaps() {
        let store = CollectionStore()
        let originals = store.elementIDs()
        store.duplicateActive()
        let copies = Set(store.active.workspace.groups.values.flatMap { $0.elements.map(\.id) })
        #expect(!copies.isEmpty)
        #expect(originals.isDisjoint(with: copies))
    }

    @Test("Deleting the only collection is refused")
    func deleteRefusesLast() {
        let store = CollectionStore()
        #expect(store.deleteActive() == nil)
        #expect(store.collections.count == 1)
    }

    @Test("Adding an import dedups ids against everything already held")
    func addDedups() {
        let store = CollectionStore()
        store.add(MockData.workspace()) // identical fixed ids to the seed
        let all = store.collections.flatMap { $0.workspace.groups.values.flatMap { $0.elements.map(\.id) } }
        #expect(Set(all).count == all.count)
    }

    @Test("Restoring refuses an empty snapshot rather than emptying the app")
    func restoreRefusesEmpty() {
        let store = CollectionStore()
        #expect(!store.restore([], activeID: ""))
        #expect(store.collections.count == 1)
    }

    @Test("adoptPersisted frees marks left by people absent from the catalogue")
    func adoptPersistedHeals() {
        let store = CollectionStore()
        var workspace = MockData.workspace()
        if var group = workspace.groups["users"], !group.elements.isEmpty {
            group.elements[0].claimedBy = NBClaim(who: "someone-gone", minutesAgo: 5)
            workspace.groups["users"] = group
        }
        let collection = NBCollection(workspace: workspace)
        let freed = store.adoptPersisted([collection], activeID: collection.id, selfMemberID: "me")
        #expect(freed == 1)
        let remaining = store.collections.flatMap { $0.workspace.groups.values.flatMap(\.elements) }.compactMap(\.claimedBy)
        #expect(remaining.isEmpty)
    }

    @Test("adoptPersisted falls back to seed data when nothing usable survives")
    func adoptPersistedFallsBack() {
        let store = CollectionStore()
        let empty = NBCollection(workspace: NBWorkspace(name: "hollow", groupOrder: [], groups: [:], members: [:]))
        store.adoptPersisted([empty], activeID: empty.id, selfMemberID: "me")
        #expect(!store.workspace.groups.isEmpty, "a collection with no groups can't hold anything")
    }

    @Test("Schema edits preserve values through a relabel")
    func applySchemaPreservesValues() {
        let store = CollectionStore()
        let groupID = "users"
        var fields = store.workspace.groups[groupID]!.fields
        fields[0].label = "e-mail address" // relabel, same stable NBField.id
        let before = store.workspace.groups[groupID]!.elements[0].values["username"]

        #expect(store.applySchema(to: groupID, name: "users", fields: fields))
        let after = store.workspace.groups[groupID]!.elements[0].values["username"]
        #expect(after == before, "a relabel must not orphan the value behind it")
    }

    @Test("A schema with no usable fields is refused")
    func applySchemaRefusesEmpty() {
        let store = CollectionStore()
        #expect(!store.applySchema(to: "users", name: "users", fields: []))
    }

    @Test("Deleting a group returns it and removes it from the order")
    func deleteGroupRemovesOrder() {
        let store = CollectionStore()
        let deleted = store.deleteGroup("users")
        #expect(deleted?.id == "users")
        #expect(!store.workspace.groupOrder.contains("users"))
        #expect(store.workspace.groups["users"] == nil)
    }
}

@Suite("ElementFormModel")
struct ElementFormModelTests {

    @Test("reset gives a blank draft in dev")
    func resetIsBlank() {
        let form = ElementFormModel()
        form.name = "typed"
        form.editingElementID = "x"
        form.reset()
        #expect(form.name.isEmpty)
        #expect(!form.isEditing)
        #expect(form.environments == [.dev])
    }

    @Test("prefill keeps environments exactly, and rescues an element that has none")
    func prefillPreservesEnvironments() {
        let form = ElementFormModel()
        let element = NBElement(id: "e", name: "n", environments: [.stg, .prd], isFavorite: false,
                                claimedBy: nil, note: "note", lastUsed: "", values: ["a": "b"])
        form.prefill(from: element)
        #expect(form.environments == [.stg, .prd])
        #expect(form.isEditing)

        let homeless = NBElement(id: "h", name: "n", environments: [], isFavorite: false,
                                 claimedBy: nil, note: "", lastUsed: "", values: [:])
        form.prefill(from: homeless)
        #expect(form.environments == [.dev], "an unsaveable form would be a dead end")
    }

    @Test("toggleEnvironment reports the refusal instead of emptying the set")
    func toggleReportsRefusal() {
        let form = ElementFormModel()
        #expect(form.toggleEnvironment(.stg))
        #expect(!form.toggleEnvironment(.all), "`.all` is a filter sentinel")
        form.environments = [.dev]
        #expect(!form.toggleEnvironment(.dev), "removing the last one is refused")
        #expect(form.environments == [.dev])
    }

    @Test("Validation catches the reserved placeholder before it reaches disk")
    func validationRejectsPlaceholder() {
        let form = ElementFormModel()
        form.name = "ok"
        form.values["password"] = AppStateStore.keychainPlaceholder
        let result = form.validated(against: [NBField(key: "password", label: "password", type: .secret)])
        #expect(result.problem != nil)
    }

    @Test("Validation trims and passes a clean draft")
    func validationTrims() {
        let form = ElementFormModel()
        form.name = "  spaced  "
        form.note = "  note  "
        let result = form.validated(against: [])
        #expect(result.name == "spaced")
        #expect(result.note == "note")
        #expect(result.problem == nil)
    }
}

@Suite("GroupFormModel")
struct GroupFormModelTests {

    @Test("A fresh form starts with two renameable fields")
    func startsUsable() {
        let form = GroupFormModel()
        #expect(form.fields.count == 2)
        #expect(!form.isEditing)
    }

    @Test("Colliding labels get distinct keys")
    func keysDeduped() {
        let fields = [
            NBField(key: "", label: "user id", type: .text),
            NBField(key: "", label: "user-id", type: .text),
        ]
        let keys = GroupFormModel.normalisedFields(fields).map(\.key)
        #expect(Set(keys).count == 2, "two labels sharing one values slot silently merged data")
    }

    @Test("Empty labels are dropped")
    func emptyLabelsDropped() {
        let fields = [
            NBField(key: "", label: "kept", type: .text),
            NBField(key: "", label: "   ", type: .text),
        ]
        #expect(GroupFormModel.normalisedFields(fields).count == 1)
    }

    @Test("An existing field keeps its key through a relabel")
    func existingKeysPreserved() {
        let original = NBField(key: "username", label: "username", type: .text)
        var relabelled = original
        relabelled.label = "e-mail"
        let result = GroupFormModel.normalisedFields([relabelled], existingByID: [original.id: original])
        #expect(result[0].key == "username")
    }

    @Test("singularise and slug behave", arguments: [("users", "user"), ("promos", "promo"), ("staff", "staff")])
    func singulariseCases(input: String, expected: String) {
        #expect(GroupFormModel.singularise(input) == expected)
    }
}

@Suite("ToastCenter")
struct ToastCenterTests {

    @Test("Posting appends, newest last")
    func posts() {
        let center = ToastCenter()
        center.post("first", color: .green)
        center.post("second", color: .red)
        #expect(center.items.map(\.message) == ["first", "second"])
    }

    @Test("The stack is capped so a burst can't outgrow the panel")
    func capped() {
        let center = ToastCenter()
        for index in 0..<(ToastCenter.visibleLimit + 3) {
            center.post("toast \(index)", color: .amber)
        }
        #expect(center.items.count == ToastCenter.visibleLimit)
        #expect(center.items.last?.message == "toast \(ToastCenter.visibleLimit + 2)", "the newest always survives")
    }

    @Test("clear empties it")
    func clears() {
        let center = ToastCenter()
        center.post("x", color: .green)
        center.clear()
        #expect(center.items.isEmpty)
    }
}

@Suite("NBDeeplinkScheme")
struct DeeplinkSchemeUnitTests {

    @Test("Normalises what people actually paste", arguments: [
        ("notchdemo", "notchdemo"),
        ("notchdemo://", "notchdemo"),
        ("notchdemo:", "notchdemo"),
        ("notchdemo.", "notchdemo"),
        ("  notchdemo  ", "notchdemo"),
        ("notchdemo://debug/login", "notchdemo"),
    ])
    func resolves(input: String, expected: String) {
        #expect(NBDeeplinkScheme.resolve(input) == expected)
    }

    @Test("The login URL percent-encodes everything a credential can contain")
    func urlEncodes() {
        let url = NBDeeplinkScheme.debugLoginURL(
            scheme: "notchdemo",
            username: "ava+test@acme.dev",
            password: "p@ss word&more=1"
        )
        let unwrapped = try! #require(url)
        #expect(unwrapped.hasPrefix("notchdemo://debug/login?user="))
        // Nothing unescaped may survive, or a password could terminate the query or be
        // read as a separator.
        #expect(!unwrapped.dropFirst("notchdemo://debug/login?".count).contains("@"))
        #expect(!unwrapped.dropFirst("notchdemo://debug/login?".count).contains(" "))
        #expect(unwrapped.components(separatedBy: "&").count == 2, "exactly one separator: user and pass")
    }

    @Test("A password-less element still produces a URL")
    func urlWithoutPassword() {
        let url = NBDeeplinkScheme.debugLoginURL(scheme: "notchdemo", username: "ava", password: nil)
        #expect(url == "notchdemo://debug/login?user=ava")
    }
}
