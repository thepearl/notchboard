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

enum SimctlBridge {
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "openurl", "booted", url]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        process.terminationHandler = { finished in
            let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let failure: Failure?
            if finished.terminationStatus == 0 {
                failure = nil
            } else if stderr.localizedCaseInsensitiveContains("no devices are booted")
                        || stderr.localizedCaseInsensitiveContains("current state: shutdown") {
                failure = .noBootedSimulator
            } else {
                failure = .failed(stderr.isEmpty ? "exit \(finished.terminationStatus)" : String(stderr.prefix(120)))
            }
            DispatchQueue.main.async { completion(failure) }
        }

        do {
            try process.run()
        } catch {
            DispatchQueue.main.async { completion(.failed(error.localizedDescription)) }
        }
    }
}
