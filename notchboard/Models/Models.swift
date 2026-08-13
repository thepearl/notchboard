//
//  Models.swift
//  notchboard
//
//  Data model transcribed from the prototype's state shape (see vision.md §6).
//

import Foundation
import SwiftUI

enum NBEnvironment: String, CaseIterable, Identifiable, Codable {
    case all = "ALL"
    case dev = "DEV"
    case stg = "STG"
    case prd = "PRD"

    var id: String { rawValue }

    /// The environments an element can actually live in. `.all` is a filter sentinel, not
    /// a place — it must never end up in `NBElement.environments`.
    static let assignable: [NBEnvironment] = [.dev, .stg, .prd]

    /// Display order, so a multi-environment element always reads "DEV STG PRD".
    var sortOrder: Int {
        switch self {
        case .all: return 0
        case .dev: return 1
        case .stg: return 2
        case .prd: return 3
        }
    }

    var color: Color {
        switch self {
        case .all: return NBColor.textDim
        case .dev: return NBColor.envDev
        case .stg: return NBColor.envStg
        case .prd: return NBColor.envPrd
        }
    }
}

/// The modifier for Notchboard's global shortcuts (the K/N chords that reach the catalogue
/// from inside Xcode or Simulator).
///
/// This is a genuine tradeoff, which is why it's a setting rather than a constant. A global
/// chord registered via Carbon is *consumed* while registered, so each option takes something
/// away from other apps:
///
/// - `.control` — ⌃K/⌃N. These are real bindings, not obscure ones: Cocoa's
///   `StandardKeyBinding.dict` maps `^k` to `deleteToEndOfParagraph:` and `^n` to `moveDown:`
///   in every macOS text field, and both zsh and bash bind them (`kill-line`,
///   `down-line-or-history`). Verified on macOS 26.
/// - `.command` — ⌘K/⌘N. The chords the panel's own copy advertises and the most natural to
///   type, but ⌘N is New File in Xcode and New Window nearly everywhere.
/// - `.optionCommand` — ⌥⌘K/⌥⌘N. Collides with almost nothing, at the cost of a third key.
///   This is what comparable utilities actually ship: a survey of Maccy, Ice, Rectangle,
///   Amethyst, MeetingBar and Clipy found none defaulting to a single modifier plus a letter,
///   and macOS itself never claims ⌘+letter because that namespace belongs to the frontmost
///   app's menu.
///
/// What makes the first two defensible here is *scoping*: Notchboard claims the chord only
/// while an iOS-development app is frontmost, and while the panel can actually respond (see
/// AppDelegate.syncHotKeyRegistration). Type in Terminal and ⌃K is kill-line again.
enum NBHotKeyModifier: String, CaseIterable, Identifiable, Codable {
    case control = "CONTROL"
    case command = "COMMAND"
    case optionCommand = "OPTION_COMMAND"

    var id: String { rawValue }

    // The Carbon flag mapping lives in GlobalHotKeys.swift, so the model layer doesn't have
    // to import Carbon.

    /// Symbol prefix for UI copy, e.g. the list footer's "＋ new user ⌃N".
    var symbolPrefix: String {
        switch self {
        case .control: return "⌃"
        case .command: return "⌘"
        case .optionCommand: return "⌥⌘"
        }
    }

    var label: String {
        switch self {
        case .control: return "⌃ Control (⌃K / ⌃N)"
        case .command: return "⌘ Command (⌘K / ⌘N)"
        case .optionCommand: return "⌥⌘ Option-Command (⌥⌘K / ⌥⌘N)"
        }
    }

}

/// Which side of the Simulator window Notchboard docks to.
enum NBDockEdge: String, CaseIterable, Identifiable, Codable {
    case right = "RIGHT"
    case left = "LEFT"

    var id: String { rawValue }
    var label: String { self == .right ? "Right edge" : "Left edge" }
}

enum NBFieldType: String, CaseIterable, Identifiable, Codable {
    case text, secret, number, bool, date, url, picker

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .text: return NBColor.typeText
        case .secret: return NBColor.typeSecret
        case .number: return NBColor.typeNumber
        case .bool: return NBColor.typeBool
        case .date: return NBColor.typeDate
        case .url: return NBColor.typeUrl
        case .picker: return NBColor.typePicker
        }
    }
}

struct NBField: Identifiable, Codable, Equatable {
    let id: UUID
    var key: String
    var label: String
    var type: NBFieldType
    /// The allowed values of a `.picker` field. Empty (the default, and the only sensible
    /// value for every other type) means the form falls back to free text — a picker with
    /// nothing to pick from would be a dead control.
    var options: [String]

    init(id: UUID = UUID(), key: String, label: String, type: NBFieldType, options: [String] = []) {
        self.id = id
        self.key = key
        self.label = label
        self.type = type
        self.options = options
    }
}

struct NBMember: Identifiable, Codable, Equatable {
    let id: String
    var name: String
}

struct NBClaim: Codable, Equatable {
    var who: String   // member id
    var claimedAt: Date

    /// Live age of the claim — drives the age labels and auto-release.
    var minutesAgo: Int {
        max(0, Int(Date().timeIntervalSince(claimedAt) / 60))
    }

    /// Human phrase for how long ago this was claimed, e.g. "12 min ago", "3 hr ago",
    /// "15 days ago". Self-contained (it includes "ago") so no caller can produce
    /// "just now ago".
    ///
    /// Deliberately a plain `String` rather than interpolating the minute count into a
    /// SwiftUI `Text`: `Text("\(someInt)")` goes through `LocalizedStringKey`, which formats
    /// integers with a grouping separator, and a claim left overnight rendered as
    /// "claimed 22,028m ago". Rolling minutes up into hours and days fixes the readability
    /// as well as the comma.
    var ageLabel: String {
        let minutes = minutesAgo
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }

        let hours = minutes / 60
        if hours < 24 { return hours == 1 ? "1 hr ago" : "\(hours) hr ago" }

        let days = hours / 24
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }

    init(who: String, claimedAt: Date = Date()) {
        self.who = who
        self.claimedAt = claimedAt
    }

    /// Convenience for seed/mock data expressed as "claimed N minutes ago".
    init(who: String, minutesAgo: Int) {
        self.init(who: who, claimedAt: Date().addingTimeInterval(TimeInterval(-minutesAgo * 60)))
    }

    // Codable is synthesised: who + claimedAt is the whole wire format. No pre-release
    // compatibility decoding (vision.md §14.5).
}

struct NBElement: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    /// Every environment this element is valid in. A set rather than a single value
    /// because the same credentials very often exist in more than one place (the same test
    /// account seeded into dev and staging), and forcing a choice made people duplicate
    /// the row. Never contains `.all`.
    var environments: Set<NBEnvironment>
    var isFavorite: Bool
    var claimedBy: NBClaim?
    var note: String
    var lastUsed: String
    var values: [String: String]
    /// When this element's *content* last changed — the last-write-wins timestamp for sync
    /// (vision.md §14.2). Two deliberate exclusions: `isFavorite` is personal and never
    /// travels, and `claimedBy` has its own topic and its own timestamp, so claim writes
    /// must not bump this (or toggling a mark would fight content conflict resolution).
    var updatedAt: Date = Date()
    /// memberID of the last editor. Breaks LWW ties deterministically: equal timestamps →
    /// the lexically greater `updatedBy` wins, on every peer, with no coordination.
    var updatedBy: String = ""

    var isClaimed: Bool { claimedBy != nil }

    /// Environments in display order (DEV, STG, PRD).
    var sortedEnvironments: [NBEnvironment] {
        environments.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// True when this element mixes production with anything else — the combination worth
    /// warning about, since a prod credential reachable from a dev build is how prod data
    /// ends up in a staging log.
    var mixesProductionWithOthers: Bool {
        environments.mixesProductionWithOthers
    }
}

extension Set where Element == NBEnvironment {
    /// The production-mixing rule itself, on the set rather than the element, because the
    /// two places that ask are an existing element and a half-typed form draft. It lived in
    /// both, spelled out by hand in the view model and as a property here — one of the two
    /// copies would eventually have been edited alone.
    var mixesProductionWithOthers: Bool {
        contains(.prd) && count > 1
    }
}

struct NBGroup: Identifiable, Codable, Equatable {
    var id: String
    var label: String
    var singular: String
    var secondaryKey: String
    var fields: [NBField]
    var elements: [NBElement]
    /// When this group's *schema* (name, fields, ordering key) last changed — the LWW
    /// timestamp for the sync schema topic. Element mutations don't touch it.
    var updatedAt: Date = Date()

    /// The single source of truth for "which of this group's fields hold secrets" — used by
    /// persistence, export, and CRUD cleanup so the rule lives in one place.
    var secretFieldKeys: [String] {
        fields.filter { $0.type == .secret }.map(\.key)
    }

    /// What a secret-typed value reads as wherever it is not deliberately revealed. One
    /// constant so the list and the detail view can't drift apart, and a fixed length on
    /// purpose — a mask sized to its value hands out the value's length for free.
    static let secretMask = "••••••••••"

    /// True when `key` names a secret-typed field of this group.
    func isSecretField(_ key: String) -> Bool {
        fields.contains { $0.key == key && $0.type == .secret }
    }

    /// One of an element's values as it may appear on screen: masked when the field that
    /// holds it is secret-typed.
    ///
    /// The reveal toggle exists only in the detail view, one field and one click at a time.
    /// The list had no equivalent and read `values[secondaryKey]` straight, and
    /// `secondaryKey` is always the group's *first* field — so any group whose schema put a
    /// secret first printed it in cleartext on every row, permanently, with nothing to hide
    /// it again. The seeded groups all lead with a non-secret field, which is the only
    /// reason it went unnoticed (vision.md §13.16).
    ///
    /// Nil when the element carries no such value at all, so callers can still tell "no
    /// value" from "a value"; an empty secret stays empty rather than growing bullets, since
    /// bullets over nothing claim a credential that was never set.
    func displayValue(_ key: String, of element: NBElement) -> String? {
        guard let value = element.values[key] else { return nil }
        guard isSecretField(key), !value.isEmpty else { return value }
        return Self.secretMask
    }
}

extension Date {
    /// LWW timestamps travel as milliseconds (SyncPayloads), so local stamps truncate to
    /// match. Without this, two peers editing within the same millisecond diverge
    /// permanently: each one's full-precision local stamp beats the other's truncated
    /// wire copy, and neither side applies.
    var truncatedToMilliseconds: Date {
        Date(timeIntervalSince1970: (timeIntervalSince1970 * 1000).rounded(.down) / 1000)
    }
}

/// A record that something was deleted, kept so the deletion itself can travel.
///
/// Absence is not a message: a peer that was offline while an element was deleted sees
/// nothing missing and would happily republish its stale copy, resurrecting the row for
/// everyone (the retained-message trap — clearing a retained topic delivers nothing to a
/// Mac that reconnects later). Deletions therefore publish a real payload carrying
/// `deletedAt`, and the local model keeps its own tombstones so a delete performed offline
/// survives relaunch and still publishes on reconnect.
struct NBTombstone: Codable, Equatable {
    enum Kind: String, Codable {
        case element, group
    }

    /// How long a tombstone is kept (and how long its retained twin is asked to live on
    /// the broker). A peer offline longer than this can resurrect the row — accepted:
    /// the alternative is tombstones accumulating forever.
    static let retention: TimeInterval = 30 * 24 * 60 * 60

    var kind: Kind
    /// The deleted element's or group's id.
    var id: String
    /// The owning group for element tombstones; nil for group tombstones.
    var groupID: String?
    var deletedAt: Date
    /// memberID of whoever deleted it.
    var by: String
}

struct NBWorkspace: Codable, Equatable {
    var name: String
    /// When the catalogue was last renamed — the LWW timestamp for the sync meta topic.
    /// Without it, two Macs that disagree about the name after a restart have nothing to
    /// compare.
    var nameUpdatedAt: Date = Date()
    var groupOrder: [String]
    var groups: [String: NBGroup]
    var members: [String: NBMember]
    /// Deletions that still need to be visible to peers (see NBTombstone). Pruned past
    /// `NBTombstone.retention` at load time in `CollectionStore.adoptPersisted`.
    var tombstones: [NBTombstone] = []

    /// Total elements across all groups — drives the onboarding join card and toast.
    var elementCount: Int { groups.values.reduce(0) { $0 + $1.elements.count } }

    /// Drops group ids in `groupOrder` that no longer exist, removes duplicates (keeping
    /// the first occurrence), and appends any groups missing from the order (sorted, for
    /// determinism), so the ordered tabs and the group map can't drift and strand the UI.
    /// Persisted/imported workspaces are user-editable, so every entry point that ingests
    /// one runs this. A duplicated id would render duplicate tabs (undefined ForEach
    /// identity) and double-count claims in the notch badge.
    mutating func reconcileGroupOrder() {
        var seen = Set<String>()
        groupOrder = groupOrder.filter { groups[$0] != nil && seen.insert($0).inserted }
        let unordered = groups.keys.filter { !seen.contains($0) }.sorted()
        groupOrder.append(contentsOf: unordered)
    }

    /// Releases claims held by someone who isn't in `members` (and isn't you).
    ///
    /// Such a claim is unreleasable and meaningless: `claimOrRelease` refuses to release a
    /// claim you don't own and the auto-release sweep skips foreign claims, so the row stays
    /// locked forever and the notch badge counts it forever. That happened for real — the old
    /// seed data shipped claims by three fictional teammates — and it can happen again via an
    /// imported file whose team you're not part of. Ingestion points run this so the state can
    /// heal itself rather than requiring the user to delete the element.
    @discardableResult
    mutating func releaseOrphanedClaims(ownedBy selfIDs: Set<String>) -> Int {
        var released = 0
        for (groupID, group) in groups {
            var group = group
            var changed = false
            for index in group.elements.indices {
                guard let claim = group.elements[index].claimedBy,
                      !selfIDs.contains(claim.who),
                      members[claim.who] == nil else { continue }
                group.elements[index].claimedBy = nil
                changed = true
                released += 1
            }
            if changed { groups[groupID] = group }
        }
        return released
    }

    /// Assigns fresh IDs to any element whose ID already appeared earlier — in the same
    /// group or another. Duplicate IDs break SwiftUI identity, make firstIndex-based
    /// actions always hit the first copy, and collide in the Keychain (whose account key
    /// is "<elementID>.<fieldKey>", with no group component), where one element's save or
    /// delete would clobber the other's secret. The first occurrence keeps its ID, and
    /// with it any stored secret; later ones get new IDs. Iterates in `groupOrder` order
    /// (then leftover groups, sorted) so the outcome is deterministic.
    mutating func deduplicateElementIDs() {
        var seen = Set<String>()
        deduplicateElementIDs(seen: &seen)
    }

    /// Multi-collection variant: the caller threads one `seen` set through every workspace
    /// so uniqueness holds across collections, not just within one (Keychain account keys
    /// carry no collection component — see NBCollection).
    mutating func deduplicateElementIDs(seen: inout Set<String>) {
        let orderedGroupIDs = groupOrder + groups.keys.filter { !groupOrder.contains($0) }.sorted()
        for groupID in orderedGroupIDs {
            guard var group = groups[groupID] else { continue }
            var changed = false
            for index in group.elements.indices {
                let element = group.elements[index]
                if seen.insert(element.id).inserted { continue }
                group.elements[index] = NBElement(
                    id: UUID().uuidString,
                    name: element.name, environments: element.environments, isFavorite: element.isFavorite,
                    claimedBy: element.claimedBy, note: element.note,
                    lastUsed: element.lastUsed, values: element.values,
                    updatedAt: element.updatedAt, updatedBy: element.updatedBy
                )
                seen.insert(group.elements[index].id)
                changed = true
            }
            if changed { groups[groupID] = group }
        }
    }

    /// The workspace with every claim removed. Exports go through this: a claim is a
    /// status light, not a document, and one frozen into a file arrives stale by
    /// construction — the tom/sara/mia bug delivered by Slack attachment (vision.md §14).
    func clearingClaims() -> NBWorkspace {
        var result = self
        for (groupID, group) in groups {
            var group = group
            var changed = false
            for index in group.elements.indices where group.elements[index].claimedBy != nil {
                group.elements[index].claimedBy = nil
                changed = true
            }
            if changed { result.groups[groupID] = group }
        }
        return result
    }

    /// Every Keychain account key ("<elementID>.<fieldKey>") for secret values in this
    /// workspace — used to purge secrets when a workspace is discarded.
    var allSecretKeychainKeys: [String] {
        groups.values.flatMap { group in
            group.secretFieldKeys.flatMap { key in
                group.elements.map { "\($0.id).\(key)" }
            }
        }
    }

    /// Applies `transform` to every secret-typed value in every group, returning the
    /// rewritten workspace. This is the single traversal that pairs `secretFieldKeys`
    /// with element values — export blanking, import blanking, and the Keychain
    /// placeholder swap all go through it, so a future change to what counts as a secret
    /// can't silently miss one of the three.
    func mappingSecretValues(_ transform: (_ elementID: String, _ fieldKey: String, _ value: String) -> String) -> NBWorkspace {
        var result = self
        for (groupID, group) in groups {
            let secretKeys = group.secretFieldKeys
            guard !secretKeys.isEmpty else { continue }
            var group = group
            for index in group.elements.indices {
                for key in secretKeys {
                    guard let value = group.elements[index].values[key] else { continue }
                    group.elements[index].values[key] = transform(group.elements[index].id, key, value)
                }
            }
            result.groups[groupID] = group
        }
        return result
    }
}
