//
//  AppStateStore.swift
//  notchboard
//
//  Persists Notchboard's workspace data + settings + onboarding completion to a JSON file
//  under Application Support, so it survives relaunch instead of resetting to mock data
//  every time. Deliberately simple (no backend yet — see vision.md §9/§11/§13.2), with
//  three hardenings on top of the naive version:
//
//  - secret-typed field values never touch the JSON: they're swapped into the Keychain on
//    save and re-injected on load (see SecretsStore)
//  - saves are debounced (scheduleSave) so rapid mutations don't rewrite the whole file per
//    keystroke; AppDelegate flushes a final save(_:) on termination
//  - the payload carries a schemaVersion, and an unreadable file is backed up (not silently
//    discarded) before falling back to a fresh first launch
//

import Foundation
import os

struct PersistedAppState: Codable, Equatable {
    /// A plain stamp written for the future: real version history begins at the first
    /// public release. Until then there is deliberately NO compatibility code here — and
    /// no version history either: the stamp stays 1 through every pre-release shape
    /// change, because an old-shaped file already resets through the corrupt-backup path
    /// in `load()` when its decode fails (decision 2026-08-07, vision.md §14.5). Bumping
    /// it would just accumulate the v1/v2 ledger the rule exists to prevent.
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var collections: [NBCollection]
    var activeCollectionID: String
    /// Stable local identity: what this user's claims are attributed to (vision.md §14.2).
    /// Generated on first launch and never changed after.
    var memberID: String
    var autoReleaseMinutes: Int
    var startExpanded: Bool
    var dockEdge: NBDockEdge
    var onboardingCompleted: Bool
    var onboardingName: String
    /// Onboarding finished while Simulator wasn't running — show the coach mark the first
    /// time it appears, even across a relaunch.
    var coachMarkPending: Bool
    var hotKeyModifier: NBHotKeyModifier
    /// "Don't warn me again" from the production-mixing dialog.
    var suppressProductionMixWarning: Bool
    /// Whether notify-when-free notifications play a sound (Settings toggle).
    var notificationSoundEnabled: Bool

    /// The active collection's catalogue — the shape tests mostly build against. Falls
    /// back to the first collection if the active id is stale.
    var workspace: NBWorkspace {
        get {
            (collections.first { $0.id == activeCollectionID } ?? collections.first)?.workspace
                ?? NBWorkspace(name: "", groupOrder: [], groups: [:], members: [:])
        }
        set {
            if let index = collections.firstIndex(where: { $0.id == activeCollectionID }) {
                collections[index].workspace = newValue
            } else if !collections.isEmpty {
                collections[0].workspace = newValue
            }
        }
    }

    init(
        collections: [NBCollection],
        activeCollectionID: String,
        memberID: String,
        autoReleaseMinutes: Int,
        startExpanded: Bool,
        dockEdge: NBDockEdge,
        onboardingCompleted: Bool,
        onboardingName: String,
        coachMarkPending: Bool = false,
        hotKeyModifier: NBHotKeyModifier = .control,
        suppressProductionMixWarning: Bool = false,
        notificationSoundEnabled: Bool = true
    ) {
        self.suppressProductionMixWarning = suppressProductionMixWarning
        self.notificationSoundEnabled = notificationSoundEnabled
        self.schemaVersion = Self.currentSchemaVersion
        self.collections = collections
        self.activeCollectionID = activeCollectionID
        self.memberID = memberID
        self.autoReleaseMinutes = autoReleaseMinutes
        self.startExpanded = startExpanded
        self.dockEdge = dockEdge
        self.onboardingCompleted = onboardingCompleted
        self.onboardingName = onboardingName
        self.coachMarkPending = coachMarkPending
        self.hotKeyModifier = hotKeyModifier
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, collections, activeCollectionID, memberID
        case autoReleaseMinutes, startExpanded, dockEdge
        case onboardingCompleted, onboardingName, coachMarkPending, hotKeyModifier
        case suppressProductionMixWarning, notificationSoundEnabled
    }

    /// Settings decode leniently (missing keys fall back to defaults) so adding a field
    /// never wipes a user's catalogue. The catalogue itself is strict: no non-empty
    /// `collections`, no load — the file takes the corrupt-backup reset path in `load()`,
    /// by design (no pre-release compatibility code; see `currentSchemaVersion`).
    /// Encoding is synthesised — nothing is written beyond the properties themselves.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        // Exact match, same rule as imports and snapshots: another version of this file is
        // another build's business, and pre-release the answer is the reset path.
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "state schema \(schemaVersion) is not this build's \(Self.currentSchemaVersion)"
            ))
        }
        collections = try container.decode([NBCollection].self, forKey: .collections)
        guard !collections.isEmpty else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "state carries no collections"
            ))
        }

        let storedActiveID = try container.decodeIfPresent(String.self, forKey: .activeCollectionID)
        activeCollectionID = collections.contains { $0.id == storedActiveID }
            ? storedActiveID!
            : collections[0].id
        memberID = try container.decodeIfPresent(String.self, forKey: .memberID) ?? UUID().uuidString

        autoReleaseMinutes = try container.decodeIfPresent(Int.self, forKey: .autoReleaseMinutes) ?? 60
        startExpanded = try container.decodeIfPresent(Bool.self, forKey: .startExpanded) ?? true
        dockEdge = try container.decodeIfPresent(NBDockEdge.self, forKey: .dockEdge) ?? .right
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        onboardingName = try container.decodeIfPresent(String.self, forKey: .onboardingName) ?? ""
        coachMarkPending = try container.decodeIfPresent(Bool.self, forKey: .coachMarkPending) ?? false
        hotKeyModifier = try container.decodeIfPresent(NBHotKeyModifier.self, forKey: .hotKeyModifier) ?? .control
        suppressProductionMixWarning = try container.decodeIfPresent(Bool.self, forKey: .suppressProductionMixWarning) ?? false
        notificationSoundEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationSoundEnabled) ?? true
    }
}

enum AppStateStore {
    private static let logger = Logger(subsystem: "flourix.notchboard", category: "persistence")

    /// What a secret field's value looks like inside state.json — the real value lives in
    /// the Keychain under "<elementID>.<fieldKey>". Internal (not private) because the
    /// sentinel is in-band with user data: the forms reject it as an entered value, which
    /// is the cheap honest fix for the collision.
    static let keychainPlaceholder = "◆keychain◆"

    private static let saveDebounce: Duration = .milliseconds(500)
    private static var pendingSave: Task<Void, Never>?

    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Notchboard", isDirectory: true)
    }

    private static var fileURL: URL {
        directoryURL.appendingPathComponent("state.json")
    }

    static var corruptBackupURL: URL {
        directoryURL.appendingPathComponent("state.json.corrupt")
    }

    /// Loads previously persisted state, if any. Returns `nil` on first run. An existing
    /// but unreadable/corrupt file is moved aside to state.json.corrupt (so the data is
    /// recoverable and the failure is visible) before treating this as a first launch.
    /// True when a previous launch moved an unreadable state file aside. Callers that do
    /// destructive cleanup keyed off "what the current workspace references" (the Keychain
    /// orphan sweep) should skip it while a recoverable backup exists.
    static var corruptBackupExists: Bool {
        FileManager.default.fileExists(atPath: corruptBackupURL.path)
    }

    /// True when THIS launch is the one that moved a state file aside. Distinct from
    /// `corruptBackupExists`, which stays true for every later launch too.
    ///
    /// Without it the reset was silent: `load()` returned nil, the app treated that as a
    /// first launch and showed onboarding, and from the user's chair a corrupt file and an
    /// app that threw their catalogue away look identical.
    private(set) static var didTakeCorruptBackupOnLoad = false

    static func load() -> PersistedAppState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            var state = try JSONDecoder().decode(PersistedAppState.self, from: data)

            // Duplicate element IDs (hand-edited file, or two collections seeded from the
            // same source) collide in the Keychain and break SwiftUI identity — resolve
            // them across *all* collections before the placeholder swap, so the first
            // occurrence keeps its ID and its stored secret.
            state.collections.deduplicateElementIDsAcrossCollections()
            for index in state.collections.indices {
                state.collections[index].workspace = restoringSecrets(into: state.collections[index].workspace)
            }
            return state
        } catch {
            logger.error("unreadable state file, backing up to state.json.corrupt: \(error)")
            try? FileManager.default.removeItem(at: corruptBackupURL)
            try? FileManager.default.moveItem(at: fileURL, to: corruptBackupURL)
            didTakeCorruptBackupOnLoad = true
            return nil
        }
    }

    /// Debounced save — the normal path for UI-driven mutations. Coalesces bursts of
    /// changes into one write. Use `save(_:)` directly only when the write must land now
    /// (app termination).
    static func scheduleSave(_ state: PersistedAppState) {
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: saveDebounce)
            guard !Task.isCancelled else { return }
            save(state)
        }
    }

    static func save(_ state: PersistedAppState) {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            var sanitised = state
            for index in sanitised.collections.indices {
                sanitised.collections[index].workspace = strippingSecrets(from: sanitised.collections[index].workspace)
            }
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(sanitised)
            try data.write(to: fileURL, options: .atomic)
            // Piggyback the snapshot cadence on successful persists: `state` still carries
            // the real secret values (sanitisation happened on a copy), which is exactly
            // what a recovery point needs. The interval gate inside makes this periodic.
            SnapshotStore.recordIfDue(collections: state.collections, activeCollectionID: state.activeCollectionID)
        } catch {
            // Best-effort persistence — a failed save shouldn't crash or block the UI.
            logger.error("failed to persist state: \(error)")
        }
    }

    // MARK: - Secret field handling

    /// Moves every secret-typed value into the Keychain and leaves a placeholder in the
    /// returned workspace, so the JSON on disk never contains a secret.
    private static func strippingSecrets(from workspace: NBWorkspace) -> NBWorkspace {
        workspace.mappingSecretValues { elementID, fieldKey, value in
            guard value != keychainPlaceholder else { return value }
            let key = "\(elementID).\(fieldKey)"
            if value.isEmpty {
                // A blanked secret must leave the Keychain too — otherwise the scrubbed
                // value stays readable under the old account key forever.
                SecretsStore.delete(for: key)
                return value
            }
            if SecretsStore.save(value, for: key) {
                return keychainPlaceholder
            }
            // The Keychain write failed (locked, denied). Persisting the placeholder
            // anyway would point at nothing and resolve to "" on the next launch —
            // permanent loss. Keep the raw value in the JSON until a later save lands;
            // the file is local-only and this is the lesser evil.
            logger.error("keychain write failed for \(key, privacy: .public); keeping value in state.json until a save lands")
            return value
        }
    }

    /// Reverse of `strippingSecrets`: swaps placeholders back for the real Keychain values.
    /// A placeholder with no matching Keychain item resolves to an empty string.
    private static func restoringSecrets(into workspace: NBWorkspace) -> NBWorkspace {
        workspace.mappingSecretValues { elementID, fieldKey, value in
            guard value == keychainPlaceholder else { return value }
            switch SecretsStore.load(for: "\(elementID).\(fieldKey)") {
            case .found(let stored):
                return stored
            case .notFound:
                return ""
            case .failure:
                // Read error (keychain locked/denied) — keep the placeholder. The save
                // path skips placeholders and never deletes their entries, so the real
                // secret survives the transient failure.
                return value
            }
        }
    }
}
