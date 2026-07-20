//
//  WorkspaceTransfer.swift
//  notchboard
//
//  Export/import a workspace as a portable JSON file, so a catalogue can be passed between
//  teammates before real sync exists (vision.md §9 — this is the local stand-in for the
//  shared backend). Secret-typed field values are stripped on export: a file that lands in
//  Slack/email/Drive must never carry credentials in the clear (same principle as keeping
//  them out of state.json — see AppStateStore/SecretsStore).
//

import Foundation

struct WorkspaceTransferFile: Codable {
    static let currentVersion = 1
    var formatVersion: Int
    var workspace: NBWorkspace

    init(workspace: NBWorkspace) {
        self.formatVersion = Self.currentVersion
        self.workspace = workspace
    }
}

enum WorkspaceTransfer {
    enum ImportError: Error {
        case unreadable
        case emptyWorkspace
    }

    /// Encodes the workspace to shareable JSON with every secret-typed value blanked. The
    /// recipient imports the catalogue's shape and non-secret data, then re-enters secrets
    /// locally (they go to their own Keychain).
    static func exportData(_ workspace: NBWorkspace) throws -> Data {
        var stripped = workspace
        for (groupID, group) in workspace.groups {
            let secretKeys = group.secretFieldKeys
            guard !secretKeys.isEmpty else { continue }
            var group = group
            for index in group.elements.indices {
                for key in secretKeys where group.elements[index].values[key] != nil {
                    group.elements[index].values[key] = ""
                }
            }
            stripped.groups[groupID] = group
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(WorkspaceTransferFile(workspace: stripped))
    }

    /// Decodes a workspace export. `groupOrder` is reconciled with `groups` the same way
    /// `NotchboardViewModel.restore` does, so an imported file can't strand the UI.
    static func importWorkspace(from data: Data) throws -> NBWorkspace {
        guard let file = try? JSONDecoder().decode(WorkspaceTransferFile.self, from: data) else {
            throw ImportError.unreadable
        }
        var workspace = file.workspace
        guard !workspace.groups.isEmpty else { throw ImportError.emptyWorkspace }
        workspace.reconcileGroupOrder()
        return workspace
    }
}
