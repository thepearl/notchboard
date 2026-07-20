//
//  Notifier.swift
//  notchboard
//
//  Thin wrapper over UserNotifications for the "notify when free" feature (vision.md §5.2):
//  when a watched element's claim is released, the user gets a local macOS notification even
//  if Notchboard is collapsed to the notch or hidden behind Simulator.
//

import Foundation
import UserNotifications
import os

enum Notifier {
    private static let logger = Logger(subsystem: "flourix.notchboard", category: "notifications")

    /// Asks for notification permission once (no-op if already decided). Safe to call at
    /// launch; the system only shows the prompt the first time.
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                logger.error("authorization request failed: \(error.localizedDescription)")
            } else {
                logger.debug("notification authorization granted: \(granted)")
            }
        }
    }

    /// Posts an immediate local notification. Silently does nothing if the user declined
    /// permission — the in-app toast still fires, so the feature degrades gracefully.
    static func notifyElementFree(name: String) {
        let content = UNMutableNotificationContent()
        content.title = "Now free: \(name)"
        content.body = "The element you were watching is available to claim."
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.error("failed to post notification: \(error.localizedDescription)")
            }
        }
    }
}
