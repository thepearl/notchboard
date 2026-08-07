//
//  CollectionStore+SyncApply.swift
//  notchboard
//
//  The inbound half of the sync seam: how a change that arrived from the room lands in
//  the catalogue. Everything here mutates WITHOUT calling `changeSink` — that is the echo
//  suppression the whole design leans on, enforced by construction rather than by a flag.
//
//  Conflict resolution is last-write-wins per element (vision.md §14.2), with three
//  hardenings the sketch doesn't spell out:
//
//  - Remote timestamps from the future are clamped to now, or one Mac with a skewed clock
//    wins every conflict permanently.
//  - Ties break on `updatedBy` (lexically greater wins) so both peers pick the same winner
//    with no coordination.
//  - Equal outcomes don't write: Observation notifies on writes, not changes (the
//    SimulatorWindowTracker rule), and replayed retained messages arrive repeatedly.
//
//  One accepted edge: if the same catalogue is joined to two rooms from one Mac, an
//  element id could arrive in a second collection. The launch-time cross-collection dedup
//  re-mints the newcomer's id (protecting the Keychain invariant), and reconcile-push then
//  offers it to its room as a new element. Noisy, convergent, and rare enough to accept.
//

import Foundation

extension CollectionStore {

    // MARK: - Elements

    /// Applies a remote element (create or edit). The incoming value carries only content
    /// — `isFavorite` and `claimedBy` are local/claim-topic state and are preserved.
    func applyRemoteElement(_ incoming: NBElement, groupID: String, collectionID: String, now: Date = Date()) -> RemoteApplyOutcome {
        guard let cIndex = collections.firstIndex(where: { $0.id == collectionID }) else { return .ignored }
        guard var group = collections[cIndex].workspace.groups[groupID] else { return .deferred }

        var candidate = incoming
        candidate.updatedAt = min(candidate.updatedAt, now) // clock-skew clamp

        // A tombstone at least as new as the edit wins; an edit newer than the tombstone
        // resurrects the element (someone kept working on it after a stale delete).
        if let stone = tombstone(.element, id: candidate.id, in: collections[cIndex].workspace),
           stone.deletedAt >= candidate.updatedAt {
            return .ignored
        }

        if let idx = group.elements.firstIndex(where: { $0.id == candidate.id }) {
            let local = group.elements[idx]
            guard remoteWins(remote: (candidate.updatedAt, candidate.updatedBy),
                             local: (local.updatedAt, local.updatedBy)) else { return .ignored }
            candidate.isFavorite = local.isFavorite
            candidate.claimedBy = local.claimedBy
            guard candidate != local else { return .ignored }
            group.elements[idx] = candidate
        } else {
            candidate.isFavorite = false
            candidate.claimedBy = nil
            group.elements.append(candidate)
            // The edit outlived a stale tombstone — drop the stone so it can't shadow
            // the resurrected element at the next launch prune-and-compare.
            collections[cIndex].workspace.tombstones.removeAll { $0.kind == .element && $0.id == candidate.id }
        }
        collections[cIndex].workspace.groups[groupID] = group
        return .applied
    }

    /// Applies a remote element deletion. Wins against a local copy whose last edit is no
    /// newer than the deletion; loses to (and is discarded in favour of) a newer local
    /// edit, which reconcile-push will republish.
    func applyRemoteElementTombstone(elementID: String, groupID: String, collectionID: String, deletedAt: Date, by: String, now: Date = Date()) -> RemoteApplyOutcome {
        guard let cIndex = collections.firstIndex(where: { $0.id == collectionID }) else { return .ignored }
        let clampedDeletedAt = min(deletedAt, now)

        if var group = collections[cIndex].workspace.groups[groupID],
           let idx = group.elements.firstIndex(where: { $0.id == elementID }) {
            let local = group.elements[idx]
            guard local.updatedAt <= clampedDeletedAt else { return .ignored }
            let removed = group.elements.remove(at: idx)
            collections[cIndex].workspace.groups[groupID] = group
            // A deletion driven from another Mac must clean this Mac's Keychain exactly
            // as a local delete would, or scrubbed secrets linger under dead keys.
            for key in group.secretFieldKeys {
                SecretsStore.delete(for: "\(removed.id).\(key)")
            }
        }

        recordTombstone(NBTombstone(kind: .element, id: elementID, groupID: groupID, deletedAt: clampedDeletedAt, by: by), collectionIndex: cIndex)
        return .applied
    }

    // MARK: - Schema

    /// Applies a remote group schema (create or edit). The incoming group's `elements` are
    /// ignored — elements travel per-element — and local elements are kept, with values
    /// filtered exactly the way a local schema edit filters them: dropped fields lose
    /// their values, de-secreted fields lose value and Keychain entry.
    func applyRemoteSchema(_ incoming: NBGroup, sortIndex: Int, collectionID: String, now: Date = Date()) -> RemoteApplyOutcome {
        guard let cIndex = collections.firstIndex(where: { $0.id == collectionID }) else { return .ignored }

        var candidate = incoming
        candidate.updatedAt = min(candidate.updatedAt, now)

        if let stone = tombstone(.group, id: candidate.id, in: collections[cIndex].workspace),
           stone.deletedAt >= candidate.updatedAt {
            return .ignored
        }

        if var local = collections[cIndex].workspace.groups[candidate.id] {
            // Schema LWW compares timestamps only: groups carry no updatedBy, and a
            // same-instant schema race is not worth the extra field.
            guard candidate.updatedAt > local.updatedAt else { return .ignored }

            let keptKeys = Set(candidate.fields.map(\.key))
            let newSecretKeys = Set(candidate.fields.filter { $0.type == .secret }.map(\.key))
            let clearedSecretKeys = Set(local.secretFieldKeys).subtracting(newSecretKeys)
            for idx in local.elements.indices {
                local.elements[idx].values = local.elements[idx].values.filter {
                    keptKeys.contains($0.key) && !clearedSecretKeys.contains($0.key)
                }
            }
            for element in local.elements {
                for key in clearedSecretKeys {
                    SecretsStore.delete(for: "\(element.id).\(key)")
                }
            }

            local.label = candidate.label
            local.singular = candidate.singular
            local.secondaryKey = candidate.secondaryKey
            local.fields = candidate.fields
            local.updatedAt = candidate.updatedAt
            collections[cIndex].workspace.groups[candidate.id] = local
        } else {
            candidate.elements = []
            collections[cIndex].workspace.groups[candidate.id] = candidate
            collections[cIndex].workspace.tombstones.removeAll { $0.kind == .group && $0.id == candidate.id }
        }

        // Position per the sender's ordering, clamped — peers may hold different counts
        // mid-replay.
        var order = collections[cIndex].workspace.groupOrder.filter { $0 != candidate.id }
        order.insert(candidate.id, at: min(max(sortIndex, 0), order.count))
        collections[cIndex].workspace.groupOrder = order
        return .applied
    }

    /// Applies a remote group deletion — the group, its elements, and their secrets.
    func applyRemoteGroupTombstone(groupID: String, collectionID: String, deletedAt: Date, by: String, now: Date = Date()) -> RemoteApplyOutcome {
        guard let cIndex = collections.firstIndex(where: { $0.id == collectionID }) else { return .ignored }
        let clampedDeletedAt = min(deletedAt, now)

        if let local = collections[cIndex].workspace.groups[groupID] {
            guard local.updatedAt <= clampedDeletedAt else { return .ignored }
            for key in local.secretFieldKeys {
                for element in local.elements {
                    SecretsStore.delete(for: "\(element.id).\(key)")
                }
            }
            collections[cIndex].workspace.groups.removeValue(forKey: groupID)
            collections[cIndex].workspace.groupOrder.removeAll { $0 == groupID }
        }

        recordTombstone(NBTombstone(kind: .group, id: groupID, groupID: nil, deletedAt: clampedDeletedAt, by: by), collectionIndex: cIndex)
        return .applied
    }

    // MARK: - Claims

    /// Applies a remote in-use mark (nil = released). Inserts the claimant into
    /// `workspace.members` FIRST — `releaseOrphanedClaims` wipes any claim whose member is
    /// unknown at the next launch, so a claim without its member is a claim that quietly
    /// vanishes overnight. Members are never removed; that is also what makes
    /// `memberName(_:)` render a name instead of a UUID.
    func applyRemoteClaim(_ claim: NBClaim?, claimantName: String, elementID: String, collectionID: String, selfID: String) -> RemoteApplyOutcome {
        guard let cIndex = collections.firstIndex(where: { $0.id == collectionID }),
              let groupID = locateElement(elementID, collectionID: collectionID),
              var group = collections[cIndex].workspace.groups[groupID],
              let idx = group.elements.firstIndex(where: { $0.id == elementID }) else { return .deferred }

        if let claim, claim.who != selfID {
            let name = claimantName.isEmpty ? claim.who : claimantName
            if collections[cIndex].workspace.members[claim.who]?.name != name {
                collections[cIndex].workspace.members[claim.who] = NBMember(id: claim.who, name: name)
            }
        }

        let previous = group.elements[idx].claimedBy
        guard previous != claim else { return .ignored }
        group.elements[idx].claimedBy = claim
        collections[cIndex].workspace.groups[groupID] = group

        if previous != nil, claim == nil {
            return .freed(group.elements[idx])
        }
        return .applied
    }

    // MARK: - Meta

    func applyRemoteMeta(name: String, updatedAt: Date, collectionID: String, now: Date = Date()) -> RemoteApplyOutcome {
        guard let cIndex = collections.firstIndex(where: { $0.id == collectionID }) else { return .ignored }
        let clamped = min(updatedAt, now)
        guard clamped > collections[cIndex].workspace.nameUpdatedAt,
              collections[cIndex].workspace.name != name else { return .ignored }
        collections[cIndex].workspace.name = name
        collections[cIndex].workspace.nameUpdatedAt = clamped
        return .applied
    }

    // MARK: - Room lifecycle

    /// Stores the room configuration on its collection. No emission — where a collection
    /// syncs is local machine state, like its deeplink scheme.
    func setRoomConfig(_ room: NBRoomConfig?, collectionID: String) {
        guard let cIndex = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        collections[cIndex].room = room
    }

    /// Empties a collection's catalogue ahead of adopting a non-empty room's state — the
    /// first-connect asymmetry (vision.md §14 plan): a Mac that has never merged with the
    /// room takes the room's ids wholesale instead of double-pushing its own re-minted
    /// copies. Callers snapshot first; this is destructive by design.
    func resetForRoomAdoption(collectionID: String) {
        guard let cIndex = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        purgeSecrets(of: collections[cIndex].workspace)
        collections[cIndex].workspace.groups = [:]
        collections[cIndex].workspace.groupOrder = []
        collections[cIndex].workspace.members = [:]
        collections[cIndex].workspace.tombstones = []
        // The room defines the name too: a freshly created local collection's stamp is
        // "now", which would beat the room's older — and only legitimate — meta payload.
        collections[cIndex].workspace.nameUpdatedAt = .distantPast
    }

    // MARK: - Lookup

    /// The owning group of an element — claim topics carry no group component.
    func locateElement(_ elementID: String, collectionID: String) -> String? {
        guard let collection = collections.first(where: { $0.id == collectionID }) else { return nil }
        return collection.workspace.groups.first { _, group in
            group.elements.contains { $0.id == elementID }
        }?.key
    }

    // MARK: - Helpers

    private func tombstone(_ kind: NBTombstone.Kind, id: String, in workspace: NBWorkspace) -> NBTombstone? {
        workspace.tombstones.first { $0.kind == kind && $0.id == id }
    }

    /// Records a tombstone idempotently, keeping the newest deletion time for an id.
    private func recordTombstone(_ stone: NBTombstone, collectionIndex cIndex: Int) {
        if let existing = collections[cIndex].workspace.tombstones.firstIndex(where: { $0.kind == stone.kind && $0.id == stone.id }) {
            if collections[cIndex].workspace.tombstones[existing].deletedAt < stone.deletedAt {
                collections[cIndex].workspace.tombstones[existing] = stone
            }
        } else {
            collections[cIndex].workspace.tombstones.append(stone)
        }
    }

    /// The LWW rule, in one place: newer timestamp wins; a tie goes to the lexically
    /// greater editor id, which is arbitrary but *the same arbitrary* on every peer.
    private func remoteWins(remote: (Date, String), local: (Date, String)) -> Bool {
        if remote.0 != local.0 { return remote.0 > local.0 }
        return remote.1 > local.1
    }
}
