//
//  SimctlBridge.swift
//  notchboard
//
//  Fires deeplinks into the booted iOS Simulator by shelling out to
//  `xcrun simctl openurl booted <url>` (vision.md §5.3/§9 "deeplink bridge", phase 3).
//  The target app's debug build must register the workspace's URL scheme and handle the
//  `<scheme>://debug/login?user=…` route — Notchboard only fires the URL.
//

import Foundation
import os

enum SimctlBridge {
    private static let logger = Logger(subsystem: "flourix.notchboard", category: "simctl")

    /// The URL with its query dropped — safe to log, since the query carries the password.
    private static func redacted(_ url: String) -> String {
        String(url.split(separator: "?").first ?? Substring(url))
    }

    enum Failure {
        case noBootedSimulator
        case failed(String)

        var userMessage: String {
            switch self {
            case .noBootedSimulator:
                return "no booted simulator — start one first"
            case .failed(let detail):
                return "deeplink failed — \(detail)"
            }
        }
    }

    /// Runs `xcrun simctl openurl booted <url>`. The process runs asynchronously off the
    /// main thread; `completion` is delivered on the main queue with `nil` on success.
    nonisolated static func openURL(_ url: String, completion: @escaping (Failure?) -> Void) {
        // Logged .public so it shows in the Xcode console / Console.app; the password lives
        // in the query, which redacted() strips.
        logger.log("running: xcrun simctl openurl booted \(redacted(url), privacy: .public)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "openurl", "booted", url]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        // Discard stdout rather than piping it: an undrained pipe that fills its ~64KB
        // buffer would block the child and hang the termination handler. simctl's stdout
        // isn't needed anyway.
        process.standardOutput = FileHandle.nullDevice

        process.terminationHandler = { finished in
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let failure: Failure?
            if finished.terminationStatus == 0 {
                failure = nil
                logger.log("simctl openurl succeeded for \(redacted(url), privacy: .public)")
            } else if stderr.localizedCaseInsensitiveContains("no devices are booted")
                        || stderr.localizedCaseInsensitiveContains("current state: shutdown") {
                failure = .noBootedSimulator
                logger.error("simctl openurl: no booted simulator (exit \(finished.terminationStatus, privacy: .public))")
            } else {
                failure = .failed(stderr.isEmpty ? "exit \(finished.terminationStatus)" : String(stderr.prefix(120)))
                // Full, untruncated stderr goes to the log even though the toast truncates.
                logger.error("simctl openurl failed (exit \(finished.terminationStatus, privacy: .public)): \(stderr.isEmpty ? "<no stderr>" : stderr, privacy: .public)")
            }
            DispatchQueue.main.async { completion(failure) }
        }

        do {
            try process.run()
        } catch {
            logger.error("could not launch xcrun: \(error.localizedDescription, privacy: .public)")
            DispatchQueue.main.async { completion(.failed(error.localizedDescription)) }
        }
    }
}
