//
//  SimctlBridge.swift
//  notchboard
//
//  Fires deeplinks into the booted iOS Simulator by shelling out to
//  `xcrun simctl openurl booted <url>` (vision.md §5.3/§9 "deeplink bridge", phase 3).
//  The target app's debug build must register the workspace's URL scheme and handle the
//  `<scheme>://debug/login?user=…` route — Notchboard only fires the URL.
//
//  The process plumbing and the argv-password trade-off live in DeeplinkBridge (shared
//  with AdbBridge — see its header); what stays here is the one thing that is simctl's
//  own: which stderr strings mean "no booted simulator" rather than a real failure.
//

import Foundation
import os

// Everything here runs off the main actor (the child process callbacks), so the members
// are explicitly nonisolated rather than picking up the project-wide MainActor default —
// see SWIFT_DEFAULT_ACTOR_ISOLATION in CLAUDE.md.
enum SimctlBridge {
    nonisolated private static let logger = Logger(subsystem: "flourix.notchboard", category: "simctl")

    /// Runs `xcrun simctl openurl booted <url>`. The process runs asynchronously off the
    /// main thread; `completion` is delivered on the main queue with `nil` on success.
    nonisolated static func openURL(_ url: String, completion: @escaping (DeeplinkFailure?) -> Void) {
        // Logged .public so it shows in the Xcode console / Console.app; the password lives
        // in the query, which redacted() strips.
        logger.log("running: xcrun simctl openurl booted \(DeeplinkBridge.redacted(url), privacy: .public)")

        DeeplinkBridge.run(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "openurl", "booted", url],
            url: url,
            logger: logger
        ) { outcome in
            switch outcome {
            case .launchFailed(let message):
                completion(.failed(message))
            case .finished(let status, _, let stderr):
                let failure: DeeplinkFailure?
                if status == 0 {
                    failure = nil
                    logger.log("simctl openurl succeeded for \(DeeplinkBridge.redacted(url), privacy: .public)")
                } else if stderr.localizedCaseInsensitiveContains("no devices are booted")
                            || stderr.localizedCaseInsensitiveContains("current state: shutdown") {
                    failure = .deviceNotAvailable(.iosSimulator)
                    logger.error("simctl openurl: no booted simulator (exit \(status, privacy: .public))")
                } else {
                    failure = .failed(stderr.isEmpty ? "exit \(status)" : String(stderr.prefix(120)))
                    // Full (sanitised) stderr goes to the log even though the toast truncates.
                    logger.error("simctl openurl failed (exit \(status, privacy: .public)): \(stderr.isEmpty ? "<no stderr>" : stderr, privacy: .public)")
                }
                completion(failure)
            }
        }
    }
}
