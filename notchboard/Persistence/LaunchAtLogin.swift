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

    /// What actually happened after a register/unregister attempt — the toggle in Settings
    /// must reflect this, and `.requiresApproval` needs its own affordance: the user
    /// previously disabled the app in System Settings → Login Items, a normal macOS state
    /// in which registration "succeeds" without enabling anything.
    enum Status: Equatable {
        case enabled
        case disabled
        case requiresApproval
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var status: Status {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        default: return .disabled
        }
    }

    /// Registers or unregisters the app as a login item and reports the resulting state,
    /// so the caller can reflect what actually happened (registration can fail — unsigned
    /// build — or land in `.requiresApproval`).
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Status {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("failed to \(enabled ? "register" : "unregister") login item: \(error.localizedDescription)")
        }
        return status
    }

    /// Opens System Settings → General → Login Items — the place where a
    /// `.requiresApproval` state is resolved.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
