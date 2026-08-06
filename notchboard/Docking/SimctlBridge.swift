//
//  SimctlBridge.swift
//  notchboard
//
//  Fires deeplinks into the booted iOS Simulator by shelling out to
//  `xcrun simctl openurl booted <url>` (vision.md §5.3/§9 "deeplink bridge", phase 3).
//  The target app's debug build must register the workspace's URL scheme and handle the
//  `<scheme>://debug/login?user=…` route — Notchboard only fires the URL.
//
//  ACCEPTED TRADEOFF — password in process arguments: simctl takes the URL as argv, and
//  the query can carry `pass=<password>`, so while the short-lived xcrun/simctl process
//  runs, the password is readable by other same-user processes (`ps`, Activity Monitor).
//  There is no argv-free way to hand simctl a URL. These are shared *test* credentials
//  and this is a local dev tool, so the exposure is accepted and documented rather than
//  silently present (see CLAUDE.md). Everything under our control — our own log lines and
//  simctl's echoed stderr — is redacted before logging.
//

import Foundation
import os

// Everything here runs off the main actor (the child process and its pipe handlers), so the
// members are explicitly nonisolated rather than picking up the project-wide MainActor
// default — see SWIFT_DEFAULT_ACTOR_ISOLATION in CLAUDE.md.
enum SimctlBridge {
    nonisolated private static let logger = Logger(subsystem: "flourix.notchboard", category: "simctl")

    /// The URL with its query dropped — safe to log, since the query carries the password.
    nonisolated static func redacted(_ url: String) -> String {
        String(url.split(separator: "?").first ?? Substring(url))
    }

    /// simctl's stderr is untrusted output that may echo the URL we passed it. Strip the
    /// full URL and the bare query string before the text reaches a toast or the unified
    /// log, so an error message can never carry the password out of the process.
    nonisolated static func sanitized(_ stderr: String, url: String) -> String {
        var output = stderr.replacingOccurrences(of: url, with: "\(redacted(url))?…")
        let parts = url.split(separator: "?", maxSplits: 1)
        if parts.count == 2 {
            output = output.replacingOccurrences(of: String(parts[1]), with: "…")
        }
        return output
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

    /// Accumulates pipe output across the readability handler's background invocations.
    /// Lock-guarded rather than actor-isolated: `Pipe`'s readability handler is a
    /// synchronous callback on a background queue, so it can't await anything.
    nonisolated private final class PipeBuffer: @unchecked Sendable {
        private var data = Data()
        private let lock = NSLock()

        init() {}

        func append(_ chunk: Data) {
            lock.lock()
            data.append(chunk)
            lock.unlock()
        }

        func drain() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
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

        // Both pipes must be drained *while the child runs*: an undrained pipe that fills
        // its ~64KB buffer blocks the child on write(2), so it never exits and the
        // termination handler never fires. stdout isn't needed, so it goes to the null
        // device; stderr is accumulated incrementally by the readability handler.
        let stderrPipe = Pipe()
        let stderrBuffer = PipeBuffer()
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            stderrBuffer.append(chunk)
        }

        process.terminationHandler = { finished in
            // The child has exited, so whatever is left in the pipe is bounded — stop the
            // incremental handler and collect the tail synchronously.
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            var errorData = stderrBuffer.drain()
            errorData.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
            let stderr = sanitized(
                String(decoding: errorData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                url: url
            )

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
                // Full (sanitised) stderr goes to the log even though the toast truncates.
                logger.error("simctl openurl failed (exit \(finished.terminationStatus, privacy: .public)): \(stderr.isEmpty ? "<no stderr>" : stderr, privacy: .public)")
            }
            DispatchQueue.main.async { completion(failure) }
        }

        do {
            try process.run()
        } catch {
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            logger.error("could not launch xcrun: \(error.localizedDescription, privacy: .public)")
            DispatchQueue.main.async { completion(.failed(error.localizedDescription)) }
        }
    }
}
