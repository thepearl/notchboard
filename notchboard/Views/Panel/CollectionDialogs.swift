//
//  CollectionDialogs.swift
//  notchboard
//
//  AppKit prompts for collection management (new/rename need a name, delete needs a real
//  confirmation). NSAlert rather than in-panel forms: these are rare, deliberate actions,
//  and the floating panel's fixed geometry is a bad place for a modal text field.
//
//  As everywhere else (see WorkspaceFileDialogs), NSApp.activate first — an accessory
//  agent's modal can otherwise open behind the frontmost app.
//

import AppKit

@MainActor
enum CollectionDialogs {
    /// Asks for a collection name. Returns nil on cancel, never an empty string.
    static func promptForName(title: String, message: String, initial: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = initial
        field.placeholderString = "collection name"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Asks for this collection's debug URL scheme. Returns nil on cancel; an empty string
    /// is a real answer (it clears the scheme and turns the deeplink button off).
    static func promptForScheme(collectionName: String, current: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Debug URL scheme for “\(collectionName)”"
        alert.informativeText = "“Login on sim” fires <scheme>://debug/login into the booted Simulator. Use the scheme your app's debug build registers — the NotchDemo sample uses notchdemo. Stored per collection, so each catalogue drives its own app. Leave empty to turn the button off."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = current
        field.placeholderString = "e.g. notchdemo"
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func confirmDelete(name: String, elementCount: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(name)”?"
        alert.informativeText = "Its \(elementCount) element\(elementCount == 1 ? "" : "s") and their secrets are removed from this Mac. Snapshots in ~/.notchboard/snapshots are the way back."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
