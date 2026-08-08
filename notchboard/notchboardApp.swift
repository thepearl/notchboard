//
//  notchboardApp.swift
//  notchboard
//
//  Created by Ghazi on 7/16/26.
//

import SwiftUI

@main
struct notchboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Notchboard has no normal window — AppDelegate creates a borderless floating panel
        // that docks to the real Simulator.app window. This empty Settings scene just
        // satisfies SwiftUI's requirement that an App have at least one Scene.
        //
        // Its generated "Settings…" command has to go, though: it claims ⌘, app-wide, and
        // answering that shortcut with this EmptyView is what opened a blank window from
        // the panel (team feedback). Removing the command group frees ⌘, for AppDelegate's
        // local key monitor, which opens the real settings window.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) { }
        }
    }
}
