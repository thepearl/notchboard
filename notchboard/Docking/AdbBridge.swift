//
//  AdbBridge.swift
//  notchboard
//
//  Fires deeplinks into a running Android emulator by shelling out to
//  `adb [-s serial] shell am start -a android.intent.action.VIEW -d '<url>'` — the
//  emulator twin of SimctlBridge. The serial (`emulator-<port>`) comes from the tracked
//  device window's title; nil falls back to adb's sole-device default.
//
//  QUOTING IS LOAD-BEARING: `adb shell` re-joins its arguments and hands them to the
//  device-side `sh`, so the URL is parsed by a *second* shell even though we spawn adb
//  with a clean argv. Unquoted, the `&` between query params truncates the intent at
//  `user=…` and backgrounds the rest. `deviceShellQuoted` single-quotes the URL for that
//  second parse.
//
//  ACCEPTED TRADEOFFS — the argv exposure shared with simctl (see DeeplinkBridge), plus
//  one of adb's own: on API ≤ 32 the system logs the intent's data URI VERBATIM to
//  logcat, credentials included (API 33+ redacts it to scheme://host/...). Shared test
//  credentials on a local dev tool, documented rather than silently present; there is no
//  runtime probing of the device's API level.
//

import Foundation
import os

// Everything here runs off the main actor (the child process callbacks), so the members
// are explicitly nonisolated — see SWIFT_DEFAULT_ACTOR_ISOLATION in CLAUDE.md.
enum AdbBridge {
    nonisolated private static let logger = Logger(subsystem: "flourix.notchboard", category: "adb")

    /// Where adb was found, resolved once per launch. A launchd GUI app has a minimal
    /// PATH, so this never consults it.
    nonisolated static let adbPath: String? = resolveAdb(
        env: ProcessInfo.processInfo.environment,
        homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
        fileExists: { FileManager.default.fileExists(atPath: $0) }
    )

    /// Runs `adb [-s serial] shell am start …`. The process runs asynchronously off the
    /// main thread; `completion` is delivered on the main queue with `nil` on success.
    nonisolated static func openURL(_ url: String, serial: String?, completion: @escaping (DeeplinkFailure?) -> Void) {
        guard let adbPath else {
            logger.error("adb not found in any known location")
            DispatchQueue.main.async { completion(.failed("adb not found — install Android platform-tools")) }
            return
        }

        var arguments: [String] = []
        if let serial { arguments += ["-s", serial] }
        arguments += ["shell", "am", "start", "-a", "android.intent.action.VIEW", "-d", deviceShellQuoted(url)]

        logger.log("running: adb \(serial.map { "-s \($0) " } ?? "", privacy: .public)shell am start -d \(DeeplinkBridge.redacted(url), privacy: .public)")

        // stdout is captured because `am start` reports on-device failures there with
        // exit 0 — "Error: Activity not started…" on a clean exit is still a failure.
        DeeplinkBridge.run(
            executable: adbPath,
            arguments: arguments,
            url: url,
            logger: logger,
            captureStdout: true
        ) { outcome in
            switch outcome {
            case .launchFailed(let message):
                completion(.failed(message))
            case .finished(let status, let stdout, let stderr):
                let failure = classify(exitStatus: status, stdout: stdout, stderr: stderr)
                switch failure {
                case nil:
                    logger.log("adb am start succeeded for \(DeeplinkBridge.redacted(url), privacy: .public)")
                case .deviceNotAvailable:
                    logger.error("adb am start: no running emulator (exit \(status, privacy: .public))")
                case .failed:
                    // Full (sanitised) output goes to the log even though the toast truncates.
                    logger.error("adb am start failed (exit \(status, privacy: .public)): \(stderr.isEmpty ? stdout : stderr, privacy: .public)")
                }
                completion(failure)
            }
        }
    }

    /// Quotes the URL for the device-side `sh` re-parse (see the header): wrapped in
    /// single quotes, with any embedded single quote spelled `'\''` (close, escaped
    /// quote, reopen) — the POSIX idiom, since nothing can be escaped inside single quotes.
    nonisolated static func deviceShellQuoted(_ url: String) -> String {
        "'" + url.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The adb discovery order: the SDK env vars, the default Android Studio SDK path,
    /// then the Homebrew and legacy /usr/local bin directories. Pure — env, home and the
    /// filesystem probe are injected so tests never touch the real machine.
    nonisolated static func resolveAdb(
        env: [String: String], homeDirectory: String, fileExists: (String) -> Bool
    ) -> String? {
        var candidates: [String] = []
        if let sdk = env["ANDROID_HOME"], !sdk.isEmpty { candidates.append("\(sdk)/platform-tools/adb") }
        if let sdk = env["ANDROID_SDK_ROOT"], !sdk.isEmpty { candidates.append("\(sdk)/platform-tools/adb") }
        candidates.append("\(homeDirectory)/Library/Android/sdk/platform-tools/adb")
        candidates.append("/opt/homebrew/bin/adb")
        candidates.append("/usr/local/bin/adb")
        return candidates.first(where: fileExists)
    }

    /// Maps what adb/am printed to a failure, or nil for success. Pure; both streams
    /// arrive already sanitised. `am start` can exit 0 while printing an Error line to
    /// stdout, so a clean exit status alone proves nothing.
    nonisolated static func classify(exitStatus: Int32, stdout: String, stderr: String) -> DeeplinkFailure? {
        if exitStatus != 0 {
            let noDevice = stderr.localizedCaseInsensitiveContains("no devices/emulators found")
                || (stderr.localizedCaseInsensitiveContains("device ")
                        && stderr.localizedCaseInsensitiveContains("not found"))
            if noDevice { return .deviceNotAvailable(.androidEmulator) }
            return .failed(stderr.isEmpty ? "exit \(exitStatus)" : String(stderr.prefix(120)))
        }
        if let errorLine = stdout
            .components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { $0.hasPrefix("Error:") }) {
            return .failed(String(errorLine.prefix(120)))
        }
        return nil
    }
}
