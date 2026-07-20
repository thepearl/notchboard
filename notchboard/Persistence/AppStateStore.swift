//
//  AppStateStore.swift
//  notchboard
//
//  Persists Notchboard's workspace data + settings + onboarding completion to a JSON file
//  under Application Support, so it survives relaunch instead of resetting to mock data
//  every time. Deliberately simple (no backend yet — see vision.md §9/§11/§13.2).
//

import Foundation

struct PersistedAppState: Codable, Equatable {
    var workspace: NBWorkspace
    var autoReleaseMinutes: Int
    var startExpanded: Bool
    var liveSyncEnabled: Bool
    var onboardingCompleted: Bool
    var onboardingName: String
}

enum AppStateStore {
    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Notchboard", isDirectory: true)
    }

    private static var fileURL: URL {
        directoryURL.appendingPathComponent("state.json")
    }

    /// Loads previously persisted state, if any. Returns `nil` on first run or if the file
    /// is missing/unreadable/corrupt (in which case callers should fall back to fresh mock
    /// data and treat this as a first launch).
    static func load() -> PersistedAppState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PersistedAppState.self, from: data)
    }

    static func save(_ state: PersistedAppState) {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Best-effort persistence — a failed save shouldn't crash or block the UI.
            print("Notchboard: failed to persist state — \(error)")
        }
    }
}
