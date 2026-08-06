//
//  AccessibilityPermission.swift
//  notchboard
//
//  Thin wrapper around the macOS Accessibility (AX) trust APIs. Notchboard needs this
//  permission to read the iOS Simulator's window frame and dock next to it — the same
//  pattern RocketSim uses (see onboarding step 4 / vision.md §4).
//

import AppKit
import ApplicationServices

enum AccessibilityPermission {
    /// Whether this process is currently trusted for Accessibility (AX) API access.
    /// Nonisolated: the tracker's poll and the onboarding poll both probe this without
    /// needing the main actor.
    nonisolated static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user via the system Accessibility dialog if not already trusted
    /// (adds Notchboard to System Settings → Privacy & Security → Accessibility).
    ///
    /// macOS only shows that dialog until the app has been added to the Accessibility
    /// list — once the user dismisses it, further calls silently return false with no UI
    /// at all. Callers must offer `openSystemSettings()` as the follow-up affordance.
    @discardableResult
    static func requestIfNeeded() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: CFDictionary = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings directly at Privacy & Security → Accessibility — the only
    /// way forward after the one-shot system prompt has been dismissed.
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
