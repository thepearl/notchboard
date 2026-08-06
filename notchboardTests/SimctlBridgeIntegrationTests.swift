//
//  SimctlBridgeIntegrationTests.swift
//  notchboardTests
//
//  Drives the real deeplink bridge against a real booted simulator, rather than stubbing
//  it. This is the one path unit tests can't fake: SimctlBridge shells out to
//  `xcrun simctl`, and everything that can go wrong (argument quoting, exit-status
//  handling, the stderr drain, the completion never firing) only shows up for real.
//
//  Skips itself when no simulator is booted, so a machine or CI runner without one still
//  gets a green suite. Pair it with SampleApp/NotchDemo, which registers the notchdemo://
//  scheme — see SampleApp/README.md.
//

import Foundation
import Testing
@testable import notchboard

@Suite("SimctlBridge against a real simulator", .serialized)
struct SimctlBridgeIntegrationTests {

    /// True when at least one simulator is booted; the bridge needs one to target.
    private static var hasBootedSimulator: Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "booted"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).contains("(Booted)")
    }

    /// Runs the bridge and waits for its completion, which is delivered on the main queue.
    private func fire(_ url: String, timeout: TimeInterval = 30) async -> SimctlBridge.Failure?? {
        await withCheckedContinuation { continuation in
            let resumed = LockedFlag()
            SimctlBridge.openURL(url) { failure in
                if resumed.setOnce() { continuation.resume(returning: .some(failure)) }
            }
            // Guard against the completion never arriving — the exact bug the stderr-drain
            // fix addressed. `nil` (the outer optional) means "never called".
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                if resumed.setOnce() { continuation.resume(returning: .none) }
            }
        }
    }

    @Test("A well-formed deeplink reaches the simulator and reports success")
    func successfulDeeplink() async throws {
        try #require(Self.hasBootedSimulator, "no booted simulator — skipping integration check")

        let result = await fire("notchdemo://debug/login?user=integration%40acme%2Edev&pass=Test%2D1")
        let failure = try #require(result, "completion never fired — the bridge hung")
        #expect(failure == nil, "expected success, got \(String(describing: failure))")
    }

    @Test("An unregistered scheme is reported as a failure, not silent success")
    func unhandledSchemeFails() async throws {
        try #require(Self.hasBootedSimulator, "no booted simulator — skipping integration check")

        let result = await fire("nbnosuchscheme://debug/login?user=x")
        let failure = try #require(result, "completion never fired — the bridge hung")
        #expect(failure != nil, "an unregistered scheme should not report success")
    }
}

/// One-shot flag so a continuation can't be resumed twice (completion + timeout racing).
private final class LockedFlag: @unchecked Sendable {
    private var used = false
    private let lock = NSLock()

    func setOnce() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}

extension SimctlBridge.Failure: @retroactive Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.noBootedSimulator, .noBootedSimulator): return true
        case (.failed(let l), .failed(let r)): return l == r
        default: return false
        }
    }
}
