//
//  AccessibilityPermission.swift
//  notchboard
//
//  Thin wrapper around the macOS Accessibility (AX) trust APIs. Notchboard needs this
//  permission to read the iOS Simulator's window frame and dock next to it — the same
//  pattern RocketSim uses (see onboarding step 4 / vision.md §4).
//

import ApplicationServices

enum AccessibilityPermission {
    /// Whether this process is currently trusted for Accessibility (AX) API access.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user via the system Accessibility dialog if not already trusted
    /// (adds Notchboard to System Settings → Privacy & Security → Accessibility).
    @discardableResult
    static func requestIfNeeded() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: CFDictionary = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
