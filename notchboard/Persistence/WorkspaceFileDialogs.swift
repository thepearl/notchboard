//
//  WorkspaceFileDialogs.swift
//  notchboard
//
//  The open/save panels for collection files, in one place because three surfaces need them:
//  the menu bar, onboarding's "import a collection file" starting point, and (next) the
//  collection switcher.
//
//  The `NSApp.activate` before `runModal()` is not optional. Notchboard runs as an accessory
//  agent (no Dock icon), so without it the panel can open behind whatever the user is looking
//  at, with no way to reach it.
//

import AppKit
import UniformTypeIdentifiers

enum WorkspaceFileDialogs {
    /// Asks for a collection file to read. Returns nil when the user cancels.
    /// Plain .json is accepted on its own merits: an export IS json inside, so a renamed
    /// or hand-written file should still be selectable here.
    @MainActor
    static func chooseImportFile(title: String = "Import Collection") -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.notchboardCollection, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = title
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Asks where to write a collection file. Returns nil when the user cancels.
    @MainActor
    static func chooseExportDestination(defaultName: String, title: String = "Export Collection") -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.notchboardCollection]
        panel.nameFieldStringValue = "\(defaultName).notchboard"
        panel.title = title
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
