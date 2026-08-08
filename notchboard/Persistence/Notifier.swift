//
//  Notifier.swift
//  notchboard
//
//  Thin wrapper over UserNotifications for the "notify when free" feature (vision.md §5.2):
//  when a watched element's claim is released, the user gets a real macOS notification even
//  if Notchboard is collapsed to the notch or hidden behind Simulator. Collapsed is the
//  normal case, and the panel is 36pt wide there — an in-app toast has nowhere to render,
//  which is exactly why this has to be a system notification rather than app chrome.
//
//  Permission is asked for at the moment of first use — when the user clicks "notify me
//  when it's free" — not at launch. An app that asks before the user has expressed any
//  interest gets denied by reflex, and a denial is sticky: the only way back is System
//  Settings. Asking at the point of intent also makes the request legible ("this is why").
//  A denial aborts the action rather than silently registering a watch that can't fire.
//

import AppKit
import Foundation
import UserNotifications
import os

enum Notifier {
    private static let logger = Logger(subsystem: "flourix.notchboard", category: "notifications")

    /// UNUserNotificationCenter.current() raises an uncatchable exception when there's no
    /// valid app bundle (e.g. run via `swift run` or a broken/adhoc bundle). Gate every
    /// entry on a real bundle id so those contexts degrade to no-notifications instead of
    /// crashing at launch.
    private static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    /// What the system says about our ability to post a banner right now.
    enum Permission {
        case granted
        /// The user said no — at some point, possibly long ago. Only System Settings can
        /// undo it, so callers must say so rather than pretending the feature armed.
        case denied
        /// No bundle (tests, `swift run`): notifications are simply not part of this run.
        case unavailable
    }

    /// Resolves permission, prompting once if the user has never been asked. Returns what
    /// the system ended up allowing, so the caller can abort visibly on a refusal.
    static func authorize() async -> Permission {
        guard isAvailable else { return .unavailable }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .denied:
            return .denied
        default:
            // .notDetermined — this is the one and only prompt the user ever sees.
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                return granted ? .granted : .denied
            } catch {
                logger.error("authorization request failed: \(error.localizedDescription)")
                return .denied
            }
        }
    }

    /// Posts an immediate local notification. `withSound` is the Settings toggle: the
    /// banner always shows, the ping is optional.
    static func notifyElementFree(name: String, withSound: Bool = true) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = "Now free: \(name)"
        content.body = "The element you were watching is free to use."
        content.sound = withSound ? .default : nil

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.error("failed to post notification: \(error.localizedDescription)")
            }
        }
    }

    /// Opens the app's row in System Settings → Notifications — the only route back from a
    /// denial, so the toast that reports one can point at it.
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
