//
//  SyncPayloads.swift
//  notchboard
//
//  The room wire format: topic grammar and payload shapes (vision.md §14.2). One room per
//  collection; all topics retained except the sync barrier, so a late joiner reconstructs
//  the entire catalogue from broker replay with no history protocol.
//
//      nb/<room>/meta                      collection name
//      nb/<room>/schema/<groupID>          group schema + position, or a group tombstone
//      nb/<room>/el/<groupID>/<elementID>  element content, or an element tombstone
//      nb/<room>/claim/<elementID>         in-use mark; EMPTY retained payload = free
//      nb/<room>/presence/<memberID>       online/offline; the broker's Last Will flips it
//      nb/<room>/sync/<memberID>           non-retained replay barrier
//
//  Every payload is sealed under the room key before it leaves the Mac (RoomCrypto) — the
//  shapes below are the *plaintext* the codec seals. Element payloads carry secret values
//  in-band: the whole message is ciphertext under exactly the key an inner envelope would
//  use, so double-sealing would add length and no strength.
//
//  Forward-compatibility contract (§14.2): every payload carries `v`, decoders ignore
//  unknown keys (Codable's default), unknown enum-ish strings degrade (an unknown field
//  type renders as text, an unknown environment is dropped) — two app versions must be
//  able to share a room.
//
//  Dates travel as millisecondsSince1970: LWW compares these values, and ISO8601's
//  second-granularity truncation would make a round-tripped timestamp lose against its
//  own local original.
//

import CryptoKit
import Foundation

// MARK: - Topics

enum SyncTopic: Equatable {
    case meta
    case schema(groupID: String)
    case element(groupID: String, elementID: String)
    case claim(elementID: String)
    case presence(memberID: String)
    case syncBarrier(memberID: String)

    /// The wildcard subscription covering a whole room.
    static func allTopics(room: String) -> String { "nb/\(room)/#" }

    func string(room: String) -> String {
        switch self {
        case .meta: return "nb/\(room)/meta"
        case .schema(let groupID): return "nb/\(room)/schema/\(groupID)"
        case .element(let groupID, let elementID): return "nb/\(room)/el/\(groupID)/\(elementID)"
        case .claim(let elementID): return "nb/\(room)/claim/\(elementID)"
        case .presence(let memberID): return "nb/\(room)/presence/\(memberID)"
        case .syncBarrier(let memberID): return "nb/\(room)/sync/\(memberID)"
        }
    }

    /// Parses an inbound topic. nil for foreign or malformed topics — a shared broker can
    /// carry unrelated traffic, and unparseable topics must be ignored, not crash.
    static func parse(_ topic: String, room: String) -> SyncTopic? {
        let prefix = "nb/\(room)/"
        guard topic.hasPrefix(prefix) else { return nil }
        let parts = topic.dropFirst(prefix.count).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        switch (parts.first, parts.count) {
        case ("meta", 1): return .meta
        case ("schema", 2): return .schema(groupID: parts[1])
        case ("el", 3): return .element(groupID: parts[1], elementID: parts[2])
        case ("claim", 2): return .claim(elementID: parts[1])
        case ("presence", 2): return .presence(memberID: parts[1])
        case ("sync", 2): return .syncBarrier(memberID: parts[1])
        default: return nil
        }
    }
}

// MARK: - Payload shapes (plaintext — always sealed before publishing)

struct SyncMetaPayload: Codable, Equatable {
    var v: Int = 1
    var name: String
    var updatedAt: Date
    var by: String
}

/// Marks a deletion on the same topic the content lived on. A real payload, deliberately:
/// clearing the retained message instead would deliver *nothing* to a peer that was
/// offline during the delete, and its stale copy would resurrect the row for everyone.
struct SyncTombstonePayload: Codable, Equatable {
    var v: Int = 1
    var deleted: Bool = true
    var deletedAt: Date
    var by: String
}

struct SyncSchemaPayload: Codable, Equatable {
    struct Field: Codable, Equatable {
        var id: UUID
        var key: String
        var label: String
        /// Raw string, not NBFieldType: an unknown type from a newer build must degrade
        /// to text, not fail the whole schema.
        var type: String
        var options: [String]
    }

    var v: Int = 1
    var id: String
    var label: String
    var singular: String
    var secondaryKey: String
    var fields: [Field]
    var sortIndex: Int
    var updatedAt: Date
    var by: String

    init(group: NBGroup, sortIndex: Int, by: String) {
        self.id = group.id
        self.label = group.label
        self.singular = group.singular
        self.secondaryKey = group.secondaryKey
        self.fields = group.fields.map {
            Field(id: $0.id, key: $0.key, label: $0.label, type: $0.type.rawValue, options: $0.options)
        }
        self.sortIndex = sortIndex
        self.updatedAt = group.updatedAt
        self.by = by
    }

    /// Elements always empty — they travel per-element.
    func toGroup() -> NBGroup {
        NBGroup(
            id: id, label: label, singular: singular, secondaryKey: secondaryKey,
            fields: fields.map {
                NBField(id: $0.id, key: $0.key, label: $0.label,
                        type: NBFieldType(rawValue: $0.type) ?? .text, options: $0.options)
            },
            elements: [], updatedAt: updatedAt
        )
    }
}

struct SyncElementPayload: Codable, Equatable {
    var v: Int = 1
    var id: String
    var name: String
    /// Raw strings; unknown environments from a newer build are dropped on decode.
    var environments: [String]
    var note: String
    var lastUsed: String
    /// Full values, secret ones included — see the header for why in-band is safe here.
    var values: [String: String]
    var updatedAt: Date
    var by: String

    /// Content only: `isFavorite` is personal and `claimedBy` has its own topic — neither
    /// belongs on the wire.
    init(element: NBElement) {
        self.id = element.id
        self.name = element.name
        self.environments = element.sortedEnvironments.map(\.rawValue)
        self.note = element.note
        self.lastUsed = element.lastUsed
        self.values = element.values
        self.updatedAt = element.updatedAt
        self.by = element.updatedBy
    }

    func toElement() -> NBElement {
        var parsed = Set(environments.compactMap(NBEnvironment.init(rawValue:)))
        parsed.remove(.all) // a filter sentinel, never a place — refuse it from the wire too
        if parsed.isEmpty { parsed = [.dev] } // an environment-less element is unrenderable
        return NBElement(
            id: id, name: name, environments: parsed, isFavorite: false,
            claimedBy: nil, note: note, lastUsed: lastUsed, values: values,
            updatedAt: updatedAt, updatedBy: by
        )
    }
}

struct SyncClaimPayload: Codable, Equatable {
    var v: Int = 1
    var memberID: String
    var name: String
    var at: Date
}

struct SyncPresencePayload: Codable, Equatable {
    enum State: String, Codable {
        case online, offline
    }

    var v: Int = 1
    var name: String
    var state: State
    var at: Date
}

/// What arrives on a content-or-tombstone topic (element and schema topics both).
enum SyncTopicMessage<Content: Codable & Equatable>: Equatable {
    case content(Content)
    case tombstone(SyncTombstonePayload)
}

// MARK: - Codec

/// Encode → seal, open → decode: the only doorway between payload shapes and wire bytes.
/// Holds the room key so nothing outside it can accidentally publish plaintext.
struct SyncCodec {
    let key: SymmetricKey

    func seal<T: Encodable>(_ payload: T) throws -> Data {
        try RoomCrypto.seal(Self.encoder.encode(payload), key: key)
    }

    func open<T: Decodable>(_ type: T.Type, from sealed: Data) throws -> T {
        try Self.decoder.decode(type, from: RoomCrypto.open(sealed, key: key))
    }

    /// Distinguishes content from a tombstone on a shared topic by probing the `deleted`
    /// flag first — cheaper and more honest than catching a full decode failure.
    func openTopicMessage<T: Codable & Equatable>(_ type: T.Type, from sealed: Data) throws -> SyncTopicMessage<T> {
        let plaintext = try RoomCrypto.open(sealed, key: key)
        if (try? Self.decoder.decode(TombstoneProbe.self, from: plaintext))?.deleted == true {
            return .tombstone(try Self.decoder.decode(SyncTombstonePayload.self, from: plaintext))
        }
        return .content(try Self.decoder.decode(type, from: plaintext))
    }

    private struct TombstoneProbe: Decodable {
        var deleted: Bool?
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys] // deterministic bytes → deterministic tests
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}
