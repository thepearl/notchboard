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
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var workspace: NBWorkspace
    var autoReleaseMinutes: Int
    var startExpanded: Bool
    var liveSyncEnabled: Bool
    var deeplinkScheme: String
    var dockEdge: NBDockEdge
    var onboardingCompleted: Bool
    var onboardingName: String

    init(
        workspace: NBWorkspace,
        autoReleaseMinutes: Int,
        startExpanded: Bool,
        liveSyncEnabled: Bool,
        deeplinkScheme: String,
        dockEdge: NBDockEdge,
        onboardingCompleted: Bool,
        onboardingName: String
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.workspace = workspace
        self.autoReleaseMinutes = autoReleaseMinutes
        self.startExpanded = startExpanded
        self.liveSyncEnabled = liveSyncEnabled
        self.deeplinkScheme = deeplinkScheme
        self.dockEdge = dockEdge
        self.onboardingCompleted = onboardingCompleted
        self.onboardingName = onboardingName
    }

    /// Settings decode leniently (missing keys fall back to defaults) so adding a field
    /// never wipes a user's workspace; only a missing/undecodable workspace is fatal to
    /// the load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        workspace = try container.decode(NBWorkspace.self, forKey: .workspace)
        autoReleaseMinutes = try container.decodeIfPresent(Int.self, forKey: .autoReleaseMinutes) ?? 60
        startExpanded = try container.decodeIfPresent(Bool.self, forKey: .startExpanded) ?? true
        liveSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .liveSyncEnabled) ?? true
        deeplinkScheme = try container.decodeIfPresent(String.self, forKey: .deeplinkScheme) ?? ""
        dockEdge = try container.decodeIfPresent(NBDockEdge.self, forKey: .dockEdge) ?? .right
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        onboardingName = try container.decodeIfPresent(String.self, forKey: .onboardingName) ?? ""
    }
}

enum AppStateStore {
    private static let logger = Logger(subsystem: "flourix.notchboard", category: "persistence")

    /// What a secret field's value looks like inside state.json — the real value lives in
    /// the Keychain under "<elementID>.<fieldKey>".
    private static let keychainPlaceholder = "◆keychain◆"

    private static let saveDebounce: Duration = .milliseconds(500)
    private static var pendingSave: Task<Void, Never>?

    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Notchboard", isDirectory: true)
    }

    private static var fileURL: URL {
        directoryURL.appendingPathComponent("state.json")
    }

    private static var corruptBackupURL: URL {
        directoryURL.appendingPathComponent("state.json.corrupt")
    }

    /// Loads previously persisted state, if any. Returns `nil` on first run. An existing
    /// but unreadable/corrupt file is moved aside to state.json.corrupt (so the data is
    /// recoverable and the failure is visible) before treating this as a first launch.
    static func load() -> PersistedAppState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            var state = try JSONDecoder().decode(PersistedAppState.self, from: data)
            state.workspace = restoringSecrets(into: state.workspace)
            return state
        } catch {
            logger.error("unreadable state file, backing up to state.json.corrupt: \(error)")
            try? FileManager.default.removeItem(at: corruptBackupURL)
            try? FileManager.default.moveItem(at: fileURL, to: corruptBackupURL)
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
            sanitised.workspace = strippingSecrets(from: state.workspace)
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(sanitised)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Best-effort persistence — a failed save shouldn't crash or block the UI.
            logger.error("failed to persist state: \(error)")
        }
    }

    // MARK: - Secret field handling

    private static func secretKeys(of group: NBGroup) -> [String] {
        group.fields.filter { $0.type == .secret }.map(\.key)
    }

    /// Moves every secret-typed value into the Keychain and leaves a placeholder in the
    /// returned workspace, so the JSON on disk never contains a secret.
    private static func strippingSecrets(from workspace: NBWorkspace) -> NBWorkspace {
        var stripped = workspace
        for (groupID, group) in workspace.groups {
            let secretKeys = secretKeys(of: group)
            guard !secretKeys.isEmpty else { continue }
            var group = group
            for index in group.elements.indices {
                for fieldKey in secretKeys {
                    guard let value = group.elements[index].values[fieldKey],
                          !value.isEmpty, value != keychainPlaceholder else { continue }
                    SecretsStore.save(value, for: "\(group.elements[index].id).\(fieldKey)")
                    group.elements[index].values[fieldKey] = keychainPlaceholder
                }
            }
            stripped.groups[groupID] = group
        }
        return stripped
    }

    /// Reverse of `strippingSecrets`: swaps placeholders back for the real Keychain values.
    /// A placeholder with no matching Keychain item resolves to an empty string.
    private static func restoringSecrets(into workspace: NBWorkspace) -> NBWorkspace {
        var restored = workspace
        for (groupID, group) in workspace.groups {
            let secretKeys = secretKeys(of: group)
            guard !secretKeys.isEmpty else { continue }
            var group = group
            for index in group.elements.indices {
                for fieldKey in secretKeys {
                    guard group.elements[index].values[fieldKey] == keychainPlaceholder else { continue }
                    let stored = SecretsStore.load(for: "\(group.elements[index].id).\(fieldKey)")
                    group.elements[index].values[fieldKey] = stored ?? ""
                }
            }
            restored.groups[groupID] = group
        }
        return restored
    }
}
