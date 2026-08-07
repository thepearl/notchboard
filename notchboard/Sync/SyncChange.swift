//
//  SyncChange.swift
//  notchboard
//
//  What CollectionStore tells the outside world when the catalogue changes — the outbound
//  half of the sync seam (vision.md §14.2). Every mutation primitive emits exactly one of
//  these through `CollectionStore.changeSink`; the sync engine turns them into room
//  publishes. The remote-apply path (CollectionStore+SyncApply) never emits, which is what
//  keeps two peers from echoing each other's changes forever.
//
//  Cases carry the owning collection id because the app holds several catalogues and each
//  syncs through its own room — a change must say which room it belongs to.
//

import Foundation

enum SyncChange: Equatable {
    /// The catalogue was renamed.
    case meta(collectionID: String, name: String, updatedAt: Date)
    /// A group was created or its schema edited. Carries the whole group — the wire codec
    /// strips the elements, which travel per-element — plus its position in `groupOrder`.
    case schema(collectionID: String, group: NBGroup, sortIndex: Int)
    /// A group was deleted. `elementIDs` lists what it held at deletion time so the engine
    /// can clear the per-element retained topics (receivers ignore elements under a
    /// tombstoned group regardless — the clears just keep the broker tidy).
    case groupDeleted(collectionID: String, groupID: String, elementIDs: [String], deletedAt: Date)
    /// An element's content changed (created or edited). Never fired for claim or
    /// favourite writes — claims have their own case and favourites are personal.
    case element(collectionID: String, groupID: String, element: NBElement)
    /// An element was deleted.
    case elementDeleted(collectionID: String, groupID: String, elementID: String, deletedAt: Date)
    /// An element's in-use mark changed. nil claim = released. `claimantName` travels
    /// because member ids mean nothing to a Mac that has never seen this member.
    case claim(collectionID: String, elementID: String, claim: NBClaim?, claimantName: String)

    /// Which collection (and therefore which room) this change belongs to.
    var collectionID: String {
        switch self {
        case .meta(let id, _, _),
             .schema(let id, _, _),
             .groupDeleted(let id, _, _, _),
             .element(let id, _, _),
             .elementDeleted(let id, _, _, _),
             .claim(let id, _, _, _):
            return id
        }
    }
}

/// What happened when a remote change was applied locally — the engine's signal for
/// buffering (`deferred`) and the view model's for notify-when-free (`freed`).
enum RemoteApplyOutcome: Equatable {
    /// The change landed (or partially landed after conflict resolution).
    case applied
    /// Resolved in favour of local state, or a no-op — nothing changed.
    case ignored
    /// A claim was cleared; carries the freed element so notify-when-free can fire.
    case freed(NBElement)
    /// The target doesn't exist here yet (element for an unseen group, claim for an
    /// unseen element). Retained replay is unordered across topics, so the engine buffers
    /// these and retries after the structural messages land.
    case deferred
}
