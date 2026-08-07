//
//  SnapshotRestoreFlow.swift
//  notchboard
//
//  The user-facing half of snapshot recovery (vision.md §14.5.2): pick a .nbsnap from
//  ~/.notchboard/snapshots, confirm the replacement, decrypt, restore all collections.
//

import AppKit
import UniformTypeIdentifiers

@MainActor
enum SnapshotRestoreFlow {
    static func run(viewModel: NotchboardViewModel) {
        guard !SnapshotStore.list().isEmpty else {
            viewModel.toast("no snapshots yet — they accumulate as you use the app", color: .amber)
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Restore Snapshot"
        panel.directoryURL = SnapshotStore.directoryURL
        panel.allowedContentTypes = [UTType(filenameExtension: "nbsnap") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let payload: SnapshotPayload
        do {
            payload = try SnapshotStore.load(from: url)
        } catch {
            viewModel.toast("couldn't read that snapshot — it may be from another Mac or another notchboard version", color: .red)
            return
        }

        // Destructive and whole-app-wide, so it gets a real confirmation, not a toast.
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Replace all collections?"
        alert.informativeText = "This restores \(payload.collections.count) collection\(payload.collections.count == 1 ? "" : "s") from \(Self.dateLabel(payload.savedAt)), replacing everything currently in Notchboard. A fresh snapshot of the current state is taken first."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // The escape hatch gets its own escape hatch: snapshot the current state (bypassing
        // the interval gate) so a mis-restore is itself reversible.
        SnapshotStore.recordIfDue(
            collections: viewModel.collections,
            activeCollectionID: viewModel.activeCollectionID,
            force: true
        )
        viewModel.restoreCollections(payload.collections, activeID: payload.activeCollectionID)
    }

    private static func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
