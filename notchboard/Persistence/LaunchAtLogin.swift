//
//  LaunchAtLogin.swift
//  notchboard
//
//  Wraps SMAppService so Notchboard can register itself as a login item — handy for a
//  utility meant to sit alongside Simulator all day. No helper bundle needed on modern
//  macOS: SMAppService.mainApp registers the app itself.
//

import Foundation
import ServiceManagement
import os

enum LaunchAtLogin {
    private static let logger = Logger(subsystem: "flourix.notchboard", category: "launch-at-login")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app as a login item. Returns the resulting state so the
    /// caller can reflect what actually happened (registration can fail, e.g. unsigned).
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("failed to \(enabled ? "register" : "unregister") login item: \(error.localizedDescription)")
        }
        return isEnabled
    }
}
