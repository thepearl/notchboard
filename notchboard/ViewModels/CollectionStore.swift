//
//  CollectionStore.swift
//  notchboard
//
//  Owns the catalogues themselves: every collection this Mac holds, which one is active,
//  and every mutation primitive that addresses an element. Extracted from
//  NotchboardViewModel, which was carrying the data layer and the UI layer in one type.
//
//  The split is drawn at UX: nothing here toasts, navigates or resets the panel. Methods
//  return what happened and the view model decides what to say about it. That is what
//  makes this the piece the eventual sync milestone can drive directly (vision.md §14) —
//  a room message arriving from another Mac needs to mutate collections without pretending
//  to be a button press.
//
//  Two invariants live here because they are ownership rules, not view concerns:
//  element ids are unique across ALL collections (Keychain account keys are
//  "<elementID>.<fieldKey>" with no collection component), and the list is never empty.
//

import Foundation
import Observation

@Observable
final class CollectionStore {
    /// Never empty: deletion refuses the last one and every replacement path falls back to
    /// seed data.
    var collections: [NBCollection]
    /// Which collection the panel is showing. Everything single-catalogue resolves through
    /// it.
    var activeCollectionID: String

    init(collections: [NBCollection]? = nil) {
        let seeded = collections?.isEmpty == false
            ? collections!
            : [NBCollection(workspace: MockData.workspace())]
        self.collections = seeded
        self.activeCollectionID = seeded[0].id
    }

    // MARK: - Active collection

    /// Falls back to the first collection so a stale id degrades gracefully instead of
    /// trapping (same posture as `NotchboardViewModel.activeGroup`).
    var active: NBCollection {
        collections.first { $0.id == activeCollectionID }
            ?? collections.first
            ?? NBCollection(workspace: NBWorkspace(name: "", groupOrder: [], groups: [:], members: [:]))
    }

    private var activeIndex: Int? {
        collections.firstIndex { $0.id == activeCollectionID } ?? (collections.isEmpty ? nil : 0)
    }

    /// The active catalogue. A get/set facade, so read-modify-write call sites read exactly
    /// as they did when the app held a single workspace.
    var workspace: NBWorkspace {
        get { active.workspace }
        set {
            guard let index = activeIndex else { return }
            collections[index].workspace = newValue
        }
    }

    /// The active collection's debug URL scheme. Per collection because each catalogue
    /// describes one app.
    var deeplinkScheme: String {
        get { active.deeplinkScheme }
        set {
            guard let index = activeIndex else { return }
            collections[index].deeplinkScheme = newValue
        }
    }

    // MARK: - Element addressing

    /// Element ids across every collection, optionally excluding one — the seed for
    /// cross-collection dedup at each ingestion point.
    func elementIDs(excluding excludedCollectionID: String? = nil) -> Set<String> {
        Set(collections.lazy
            .filter { $0.id != excludedCollectionID }
            .flatMap { $0.workspace.groups.values }
            .flatMap { $0.elements.map(\.id) })
    }

    /// Mutates an element in the active collection's named group.
    func mutate(_ elementID: String, in groupID: String, _ change: (inout NBElement) -> Void) {
        mutate(elementID, group: groupID, collection: activeCollectionID, change)
    }

    /// Fully-addressed mutation. Async completions must use this: an element's owning group
    /// *and* collection have to be captured at fire time, or a mid-flight switch lands the
    /// change in whatever happens to be active when the callback runs.
    func mutate(_ elementID: String, group groupID: String, collection collectionID: String, _ change: (inout NBElement) -> Void) {
        guard let cIndex = collections.firstIndex(where: { $0.id == collectionID }),
              var group = collections[cIndex].workspace.groups[groupID],
              let idx = group.elements.firstIndex(where: { $0.id == elementID }) else { return }
        change(&group.elements[idx])
        collections[cIndex].workspace.groups[groupID] = group
    }

    func element(_ elementID: String, group groupID: String, collection collectionID: String) -> NBElement? {
        collections.first { $0.id == collectionID }?
            .workspace.groups[groupID]?
            .elements.first { $0.id == elementID }
    }

    // MARK: - Collection lifecycle

    func contains(_ id: String) -> Bool {
        collections.contains { $0.id == id }
    }

    @discardableResult
    func create(named name: String) -> NBCollection {
        let collection = NBCollection(workspace: MockData.emptyWorkspace(name: name))
        collections.append(collection)
        activeCollectionID = collection.id
        return collection
    }

    /// Duplicates the active collection. Every element in the copy gets a fresh id — they
    /// all collide with the source by definition — so the copy's secrets land under their
    /// own Keychain keys instead of aliasing the original's.
    @discardableResult
    func duplicateActive() -> NBCollection {
        var seen = elementIDs()
        var copyWorkspace = active.workspace
        copyWorkspace.name += " copy"
        copyWorkspace.deduplicateElementIDs(seen: &seen)
        let copy = NBCollection(deeplinkScheme: active.deeplinkScheme, workspace: copyWorkspace)
        collections.append(copy)
        activeCollectionID = copy.id
        return copy
    }

    /// Deletes the active collection and purges its Keychain secrets, returning the one
    /// removed. Nil when it was the only collection — a panel with zero catalogues is not a
    /// state anything else handles.
    func deleteActive() -> NBCollection? {
        guard collections.count > 1 else { return nil }
        let doomed = active
        purgeSecrets(of: doomed.workspace)
        collections.removeAll { $0.id == doomed.id }
        activeCollectionID = collections[0].id
        return doomed
    }

    // MARK: - Ingestion

    /// Adds an imported catalogue alongside the existing ones and makes it active. Nothing
    /// is destroyed.
    @discardableResult
    func add(_ imported: NBWorkspace, deeplinkScheme: String = "") -> NBCollection {
        var clean = imported
        clean.reconcileGroupOrder()
        var seen = elementIDs()
        clean.deduplicateElementIDs(seen: &seen)
        let collection = NBCollection(deeplinkScheme: deeplinkScheme, workspace: clean)
        collections.append(collection)
        activeCollectionID = collection.id
        return collection
    }

    /// Swaps the active collection's catalogue, purging the outgoing one's Keychain entries
    /// — nothing references them once it's gone.
    func replaceActive(with incoming: NBWorkspace) {
        purgeSecrets(of: workspace)
        var clean = incoming
        clean.reconcileGroupOrder()
        // Duplicate ids — within the incoming file or against the *other* collections —
        // would collide in the Keychain and make row actions hit the wrong element.
        var seen = elementIDs(excluding: activeCollectionID)
        clean.deduplicateElementIDs(seen: &seen)
        workspace = clean
    }

    /// Replaces every collection from a decrypted snapshot. Whole-app-wide on purpose: a
    /// snapshot is a consistent moment in time, and restoring half of one would manufacture
    /// exactly the inconsistency it exists to undo. Returns false when there's nothing to
    /// restore.
    func restore(_ incoming: [NBCollection], activeID: String) -> Bool {
        guard !incoming.isEmpty else { return false }
        for collection in collections {
            purgeSecrets(of: collection.workspace)
        }
        var restored = incoming
        for index in restored.indices {
            restored[index].workspace.reconcileGroupOrder()
        }
        restored.deduplicateElementIDsAcrossCollections()
        collections = restored
        activeCollectionID = restored.contains { $0.id == activeID } ? activeID : restored[0].id
        return true
    }

    /// Load-time sanitisation of persisted state: reconcile ordering, free claims held by
    /// people absent from the catalogue, drop empty collections, and fall back to seed data
    /// if nothing usable survives. Returns how many claims were freed, which the caller
    /// reports.
    @discardableResult
    func adoptPersisted(_ persisted: [NBCollection], activeID: String, selfMemberID: String) -> Int {
        var restored = persisted
        var orphaned = 0
        for index in restored.indices {
            restored[index].workspace.reconcileGroupOrder()
            // A claim by someone absent from `members` can never be released through the
            // UI, so it would lock the row and inflate the notch badge permanently.
            orphaned += restored[index].workspace.releaseOrphanedClaims(ownedBy: [selfMemberID])
        }
        // A collection with no groups can't hold or accept anything.
        restored.removeAll { $0.workspace.groups.isEmpty }
        if restored.isEmpty {
            restored = [NBCollection(workspace: MockData.workspace())]
        }
        collections = restored
        activeCollectionID = restored.contains { $0.id == activeID } ? activeID : restored[0].id
        return orphaned
    }

    // MARK: - Elements
    //
    // These live here rather than in the view model because deleting an element also
    // deletes its Keychain entries: the secret lifecycle belongs with whoever owns the
    // data, or the two drift and orphaned secrets accumulate.

    func appendElement(_ element: NBElement, to groupID: String) {
        guard var group = workspace.groups[groupID] else { return }
        group.elements.append(element)
        workspace.groups[groupID] = group
    }

    /// Removes an element and its secrets, returning it so the caller can report what went.
    @discardableResult
    func deleteElement(_ elementID: String, from groupID: String) -> NBElement? {
        guard var group = workspace.groups[groupID],
              let idx = group.elements.firstIndex(where: { $0.id == elementID }) else { return nil }
        let element = group.elements.remove(at: idx)
        workspace.groups[groupID] = group
        for key in group.secretFieldKeys {
            SecretsStore.delete(for: "\(element.id).\(key)")
        }
        return element
    }

    // MARK: - Groups

    func addGroup(_ group: NBGroup) {
        workspace.groups[group.id] = group
        workspace.groupOrder.append(group.id)
    }

    /// Applies an edited schema to an existing group.
    ///
    /// Fields that already existed (matched by their stable `NBField.id`) keep their `key`,
    /// so element values survive a relabel; only new fields derive a key from their label.
    /// A field that stops being a secret — removed, or retyped — has its value dropped and
    /// its Keychain entry deleted, because otherwise the previously-protected value would
    /// survive in memory and land in state.json in cleartext on the next save.
    func applySchema(to groupID: String, name: String, fields draftFields: [NBField]) -> Bool {
        guard var group = workspace.groups[groupID] else { return false }

        let existingByID = Dictionary(uniqueKeysWithValues: group.fields.map { ($0.id, $0) })
        let fields = GroupFormModel.normalisedFields(draftFields, existingByID: existingByID)
        guard let firstField = fields.first else { return false }

        let keptKeys = Set(fields.map(\.key))
        let newSecretKeys = Set(fields.filter { $0.type == .secret }.map(\.key))
        let clearedSecretKeys = Set(group.secretFieldKeys).subtracting(newSecretKeys)
        for idx in group.elements.indices {
            group.elements[idx].values = group.elements[idx].values.filter {
                keptKeys.contains($0.key) && !clearedSecretKeys.contains($0.key)
            }
        }
        for element in group.elements {
            for key in clearedSecretKeys {
                SecretsStore.delete(for: "\(element.id).\(key)")
            }
        }

        group.label = name.lowercased()
        group.singular = GroupFormModel.singularise(name)
        group.fields = fields
        group.secondaryKey = firstField.key
        workspace.groups[groupID] = group
        return true
    }

    /// Deletes a group, its elements and all their secrets. Returns the group so the caller
    /// can name it.
    @discardableResult
    func deleteGroup(_ groupID: String) -> NBGroup? {
        guard let group = workspace.groups[groupID] else { return nil }
        for key in group.secretFieldKeys {
            for element in group.elements {
                SecretsStore.delete(for: "\(element.id).\(key)")
            }
        }
        workspace.groups.removeValue(forKey: groupID)
        workspace.groupOrder.removeAll { $0 == groupID }
        return group
    }

    // MARK: - Secrets

    private func purgeSecrets(of workspace: NBWorkspace) {
        for key in workspace.allSecretKeychainKeys {
            SecretsStore.delete(for: key)
        }
    }
}
