//
//  ElementDialogs.swift
//  notchboard
//
//  Confirmation for deleting an element. A real modal rather than the old two-step inline
//  "delete… / really delete?" button, because the action now lives in a menu where a
//  second click on the same spot is exactly what the user is already doing.
//

import AppKit

@MainActor
enum ElementDialogs {
    static func confirmDelete(name: String, hasSecrets: Bool) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(name)”?"
        alert.informativeText = hasSecrets
            ? "Its values and their Keychain secrets are removed from this Mac. Snapshots in ~/.notchboard/snapshots are the way back."
            : "Its values are removed from this Mac. Snapshots in ~/.notchboard/snapshots are the way back."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}

/// Same posture for a whole group: one warning alert with the count, not an inline button
/// that turns into a second inline button (team feedback — the two-step control read as a
/// bug, and it sat at the bottom of a scroll view where a destructive action shouldn't be).
@MainActor
enum GroupDialogs {
    static func confirmDelete(label: String, elementCount: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete the “\(label)” group?"
        alert.informativeText = elementCount == 0
            ? "It has no elements. This can't be undone from inside notchboard."
            : "Its \(elementCount) element\(elementCount == 1 ? "" : "s") go with it, secrets included."
        alert.addButton(withTitle: "Delete Group")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
