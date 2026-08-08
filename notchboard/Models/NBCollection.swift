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

/// Where a collection's team room lives (vision.md §14.2/§14.3). This whole struct is
/// shareable — it IS the invite (RoomInvite base64s it) and it travels inside exports —
/// because nothing in it is usable without the room password, which never sits here: it
/// lives in the Keychain (RoomKeyStore), shared out of band like a wifi password.
struct NBRoomConfig: Codable, Equatable {
    /// Broker address: "mqtts://host[:8883]" or "wss://host[:443]/path" (the
    /// corp-firewall fallback). May carry a username ("mqtts://user@host") for brokers
    /// with shared credentials.
    var brokerURL: String
    /// Room slug — one room per collection, so this names the collection on the broker.
    var room: String
    /// The broker account's password, AES-GCM sealed under the room key — nil for brokers
    /// without auth. The host types it once at setup; sealed, it can travel in invites and
    /// exports, and only room-password holders can open it (the §14.3 trust model: the
    /// account is team-shared). Sealing/unsealing is SyncEngine's job, because both need
    /// the derived key.
    var sealedBrokerPassword: Data?
    /// Gates the first-connect asymmetry: false means this Mac has never merged with the
    /// room, so a non-empty room replaces the local copy (after a forced snapshot) instead
    /// of merging — the rule that keeps two teammates who imported the same file from
    /// double-pushing every row.
    var firstSyncCompleted: Bool = false

    /// The broker's host, for key derivation (the room salt binds to host + room) and
    /// Keychain account keys. nil when the URL doesn't parse — callers refuse loudly.
    var brokerHost: String? {
        URL(string: brokerURL)?.host()
    }

    /// Lowercased [a-z0-9-] slug, or nil if nothing valid survives. Same posture as
    /// NBDeeplinkScheme.resolve: normalise what people actually paste, refuse the rest.
    static func normalisedSlug(_ raw: String) -> String? {
        let slug = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        guard !slug.isEmpty,
              slug.allSatisfy({ $0.isLowercase && $0.isASCII || $0.isNumber || $0 == "-" }) else {
            return nil
        }
        return slug
    }
}

struct NBCollection: Identifiable, Codable, Equatable {
    let id: String
    /// The target app's debug URL scheme for "login on sim". Per collection, because each
    /// catalogue describes one app: switching collections switches the app you deeplink into.
    var deeplinkScheme: String
    /// The team room this collection syncs through, if any. nil = local-only (the solo
    /// persona is the app with this field empty, §14.1).
    var room: NBRoomConfig?
    var workspace: NBWorkspace

    /// Passthrough, not a second stored field — a stored copy could drift from the
    /// workspace's own name and the header would lie.
    var name: String {
        get { workspace.name }
        set { workspace.name = newValue }
    }

    init(id: String = UUID().uuidString, deeplinkScheme: String = "", room: NBRoomConfig? = nil, workspace: NBWorkspace) {
        self.id = id
        self.deeplinkScheme = deeplinkScheme
        self.room = room
        self.workspace = workspace
    }

    private enum CodingKeys: String, CodingKey {
        case id, deeplinkScheme, room, workspace
    }

    /// Lenient by design: only the workspace is fatal. `id`, `deeplinkScheme` and `room`
    /// are local-only, settings-like fields (they never travel in exports as part of the
    /// collection — the room address travels separately in the transfer file), so a
    /// hand-edited file missing them heals with fresh defaults — the same leniency the
    /// persisted settings get, and not a compatibility path.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        deeplinkScheme = try container.decodeIfPresent(String.self, forKey: .deeplinkScheme) ?? ""
        room = try container.decodeIfPresent(NBRoomConfig.self, forKey: .room)
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
