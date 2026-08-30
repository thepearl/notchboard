//
//  DeeplinkBridge.swift
//  notchboard
//
//  The plumbing both deeplink bridges (SimctlBridge, AdbBridge) share: the child-process
//  run loop with its drain-while-running discipline, and the redaction that keeps the
//  password out of everything we log or toast. Classification of what the tool printed
//  stays in each bridge — the strings are tool-specific — but redaction cannot: both
//  tools echo the command line (URL included) into their error output.
//
//  ACCEPTED TRADEOFF — password in process arguments: both simctl and adb take the URL as
//  argv, and the query can carry `pass=<password>`, so while the short-lived child process
//  runs, the password is readable by other same-user processes (`ps`, Activity Monitor).
//  There is no argv-free way to hand either tool a URL. These are shared *test*
//  credentials and this is a local dev tool, so the exposure is accepted and documented
//  rather than silently present (see CLAUDE.md). Everything under our control — our own
//  log lines and the tools' echoed output — is redacted before logging.
//

import Foundation
import os

/// Why a deeplink didn't fire, phrased per target so the toast tells the user which
/// device to start. Replaces the old per-bridge failure enums — the view model handles
/// one shape whatever the router picked.
enum DeeplinkFailure {
    case deviceNotAvailable(DeviceKind)
    case failed(String)

    var userMessage: String {
        switch self {
        case .deviceNotAvailable(.iosSimulator):
            return "no booted simulator — start one first"
        case .deviceNotAvailable(.androidEmulator):
            return "no running emulator — start one first"
        case .failed(let detail):
            return "deeplink failed — \(detail)"
        }
    }
}

// Everything here runs off the main actor (the child process and its pipe handlers), so the
// members are explicitly nonisolated rather than picking up the project-wide MainActor
// default — see SWIFT_DEFAULT_ACTOR_ISOLATION in CLAUDE.md.
enum DeeplinkBridge {
    /// The URL with its query dropped — safe to log, since the query carries the password.
    nonisolated static func redacted(_ url: String) -> String {
        String(url.split(separator: "?").first ?? Substring(url))
    }

    /// A tool's output is untrusted text that may echo the URL we passed it. Strip the
    /// full URL and the bare query string before the text reaches a toast or the unified
    /// log, so an error message can never carry the password out of the process.
    nonisolated static func sanitized(_ output: String, url: String) -> String {
        var output = output.replacingOccurrences(of: url, with: "\(redacted(url))?…")
        let parts = url.split(separator: "?", maxSplits: 1)
        if parts.count == 2 {
            output = output.replacingOccurrences(of: String(parts[1]), with: "…")
        }
        return output
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

    /// What running the child produced. Both streams arrive sanitised and trimmed.
    enum Outcome {
        /// The executable could not be spawned at all (missing binary, permissions).
        case launchFailed(String)
        case finished(status: Int32, stdout: String, stderr: String)
    }

    /// Runs the child asynchronously off the main thread and delivers its outcome on the
    /// main queue. Both pipes are drained *while the child runs*: an undrained pipe that
    /// fills its ~64KB buffer blocks the child on write(2), so it never exits and the
    /// termination handler never fires. `captureStdout` exists because adb reports
    /// on-device failures on stdout with exit 0; simctl's stdout goes to the null device.
    nonisolated static func run(
        executable: String,
        arguments: [String],
        url: String,
        logger: Logger,
        captureStdout: Bool = false,
        completion: @escaping (Outcome) -> Void
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stderrPipe = Pipe()
        let stderrBuffer = PipeBuffer()
        process.standardError = stderrPipe
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            stderrBuffer.append(chunk)
        }

        let stdoutPipe: Pipe?
        let stdoutBuffer = PipeBuffer()
        if captureStdout {
            let pipe = Pipe()
            process.standardOutput = pipe
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                stdoutBuffer.append(chunk)
            }
            stdoutPipe = pipe
        } else {
            process.standardOutput = FileHandle.nullDevice
            stdoutPipe = nil
        }

        process.terminationHandler = { finished in
            // The child has exited, so whatever is left in the pipes is bounded — stop the
            // incremental handlers and collect the tails synchronously.
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            var errorData = stderrBuffer.drain()
            errorData.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

            var outputData = Data()
            if let stdoutPipe {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                outputData = stdoutBuffer.drain()
                outputData.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            }

            let clean = { (data: Data) in
                sanitized(
                    String(decoding: data, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    url: url
                )
            }
            let outcome = Outcome.finished(
                status: finished.terminationStatus, stdout: clean(outputData), stderr: clean(errorData)
            )
            DispatchQueue.main.async { completion(outcome) }
        }

        do {
            try process.run()
        } catch {
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            stdoutPipe?.fileHandleForReading.readabilityHandler = nil
            logger.error("could not launch \(executable, privacy: .public): \(error.localizedDescription, privacy: .public)")
            DispatchQueue.main.async { completion(.launchFailed(error.localizedDescription)) }
        }
    }
}
