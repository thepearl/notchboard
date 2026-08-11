//
//  OnboardingDialogs.swift
//  notchboard
//
//  The one confirmation guarding a replay of setup.
//
//  Replaying is not a read-only tour: step 3 applies a starting point, and its default is
//  "load sample data", so walking the flow again replaces the active collection and deletes
//  its Keychain secrets. Settings offered that behind a single unconfirmed click on the only
//  control there that looks like a reset — and once inside there was no cancel, since quitting
//  only postponed the same dialog to the next launch.
//
//  An alert with a count, not an inline two-step button: the same posture as ElementDialogs
//  and CollectionDialogs (vision.md §13.13).
//

import AppKit

@MainActor
enum OnboardingDialogs {
    static func confirmReplay(collectionName: String, elementCount: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Run setup again?"
        alert.informativeText = elementCount == 0
            ? "Finishing it replaces “\(collectionName)”. Snapshots in ~/.notchboard/snapshots are the way back."
            : "Finishing it replaces “\(collectionName)” and its \(elementCount) element\(elementCount == 1 ? "" : "s"). Snapshots in ~/.notchboard/snapshots are the way back."
        alert.addButton(withTitle: "Run Setup")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
