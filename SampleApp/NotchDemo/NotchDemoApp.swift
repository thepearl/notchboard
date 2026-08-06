//
//  NotchDemoApp.swift
//  NotchDemo
//
//  The standing target app for Notchboard's deeplink bridge. This is what a real team's
//  app needs to integrate: register the URL scheme (see Info.plist) and handle the
//  debug-login route (see ContentView.onOpenURL). Debug builds only, in a real product.
//

import SwiftUI

@main
struct NotchDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
