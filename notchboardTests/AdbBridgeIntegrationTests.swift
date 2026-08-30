//
//  AdbBridgeIntegrationTests.swift
//  notchboardTests
//
//  Drives the real adb bridge against a real running emulator — the adb twin of
//  SimctlBridgeIntegrationTests, covering what unit tests can't fake: the device-side
//  shell re-parse of the quoted URL, adb's exit-0-with-Error-on-stdout habit, the stream
//  drains, and the completion actually firing.
//
//  Skipped as a whole unless an emulator is attached (EmulatorProbe); the success path is
//  additionally gated on NotchDemoAndroid being installed, since without it `am start`
//  reports the exact failure the unregistered-scheme test asserts against — see
//  SampleApp/NotchDemoAndroid/README.md for the install one-liners.
//

import Foundation
import Testing
@testable import notchboard

@Suite("AdbBridge against a real emulator", .serialized,
       .enabled(if: EmulatorProbe.hasRunningEmulator,
                "needs a running Android emulator — see SampleApp/NotchDemoAndroid/README.md"))
struct AdbBridgeIntegrationTests {

    /// Runs the bridge and waits for its completion, which is delivered on the main queue.
    private func fire(_ url: String, serial: String? = nil, timeout: TimeInterval = 30) async -> DeeplinkFailure?? {
        await withCheckedContinuation { continuation in
            let resumed = LockedFlag()
            AdbBridge.openURL(url, serial: serial) { failure in
                if resumed.setOnce() { continuation.resume(returning: .some(failure)) }
            }
            // Guard against the completion never arriving. `nil` (the outer optional)
            // means "never called".
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                if resumed.setOnce() { continuation.resume(returning: .none) }
            }
        }
    }

    @Test("An unregistered scheme is reported as a failure, not silent success")
    func unhandledSchemeFails() async throws {
        // This is the end-to-end proof of the quoting: the URL's & must survive the
        // device-side sh for am to even parse the intent it then fails to resolve.
        let result = await fire("nbnosuchscheme://debug/login?user=x&pass=y")
        let failure = try #require(result, "completion never fired — the bridge hung")
        #expect(failure != nil, "an unregistered scheme should not report success")
    }

    @Test("A serial that names no device maps to device-not-available")
    func bogusSerialFails() async throws {
        let result = await fire("notchdemo://debug/login?user=x", serial: "emulator-9999")
        let failure = try #require(result, "completion never fired — the bridge hung")
        #expect(failure == .deviceNotAvailable(.androidEmulator))
    }

    @Test("A well-formed deeplink reaches the emulator and reports success",
          .enabled(if: EmulatorProbe.hasNotchDemoInstalled,
                   "needs NotchDemoAndroid installed — see SampleApp/NotchDemoAndroid/README.md"))
    func successfulDeeplink() async throws {
        let result = await fire("notchdemo://debug/login?user=integration%40acme%2Edev&pass=Test%2D1")
        let failure = try #require(result, "completion never fired — the bridge hung")
        #expect(failure == nil, "expected success, got \(String(describing: failure))")
    }
}
