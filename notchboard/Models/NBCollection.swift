//
//  NBCollection.swift
//  notchboard
//
//  A collection wraps one whole catalogue (an NBWorkspace) together with the local-only
//  state that belongs to *this machine's* copy of it: a local identity and the deeplink
//  scheme of the app it drives. Postman-style: the app holds several, the panel shows one.
//
//  Why a wrapper rather than fields on NBWorkspace (vision.md §14, plan "Phase 2"):
//  - The id must be local so importing the same export twice yields two distinct
//    collections. If the id travelled inside the shared payload, it couldn't.
//  - NBWorkspace is the payload of every .notchboard export ever written, with synthesised
//    Codable. A new non-optional stored property would fail to decode every existing file,
//    and a failed state.json decode moves the file aside as corrupt.
//

import Foundation

struct NBCollection: Identifiable, Codable, Equatable {
    let id: String
    /// The target app's debug URL scheme for "login on sim". Per collection, because each
    /// catalogue describes one app: switching collections switches the app you deeplink into.
    var deeplinkScheme: String
    var workspace: NBWorkspace

    /// Passthrough, not a second stored field — a stored copy could drift from the
    /// workspace's own name and the header would lie.
    var name: String {
        get { workspace.name }
        set { workspace.name = newValue }
    }

    init(id: String = UUID().uuidString, deeplinkScheme: String = "", workspace: NBWorkspace) {
        self.id = id
        self.deeplinkScheme = deeplinkScheme
        self.workspace = workspace
    }

    private enum CodingKeys: String, CodingKey {
        case id, deeplinkScheme, workspace
    }

    /// Lenient by design: only the workspace is fatal. `id` and `deeplinkScheme` are
    /// local-only, settings-like fields (they never travel in exports), so a hand-edited
    /// file missing them heals with fresh defaults — the same leniency the persisted
    /// settings get, and not a compatibility path.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        deeplinkScheme = try container.decodeIfPresent(String.self, forKey: .deeplinkScheme) ?? ""
        workspace = try container.decode(NBWorkspace.self, forKey: .workspace)
    }
}

extension Array where Element == NBCollection {
    /// Every Keychain account key referenced by *any* collection. The launch-time orphan
    /// sweep must be given this, never a single collection's keys — passing only the active
    /// collection's would delete every other collection's secrets on the next launch
    /// (the landmine the plan calls out at AppDelegate's pruneOrphans call).
    var allSecretKeychainKeys: [String] {
        flatMap { $0.workspace.allSecretKeychainKeys }
    }

    /// Element-id uniqueness must span collections, because Keychain account keys are
    /// "<elementID>.<fieldKey>" with no collection component. Runs the same first-keeps-id
    /// policy as the single-workspace dedup, threading one `seen` set through all of them
    /// in stable order.
    mutating func deduplicateElementIDsAcrossCollections() {
        var seen = Set<String>()
        for index in indices {
            self[index].workspace.deduplicateElementIDs(seen: &seen)
        }
    }
}
