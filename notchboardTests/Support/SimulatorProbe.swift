//
//  SimulatorProbe.swift
//  notchboardTests
//
//  The skip gate for the suite that needs a booted iOS Simulator to fire a deeplink into.
//
//  It lives out here, next to BrokerProbe, for one mechanical reason: a `.enabled(if:)` suite
//  trait is written in the attribute on the type, so it cannot reach a `private static` member
//  of the type it is annotating. Sharing the shape with BrokerProbe also keeps the two gates
//  reading the same way.
//

import Foundation

enum SimulatorProbe {
    /// The sample app that registers the `notchdemo://` scheme the bridge fires into.
    /// SampleApp/NotchDemo.xcodeproj sets this as its PRODUCT_BUNDLE_IDENTIFIER.
    private static let demoBundleID = "flourix.notchdemo"

    /// True when at least one simulator is booted; the bridge needs one to target. Computed
    /// once per process — spawning `simctl` per test would dominate the suite's runtime.
    nonisolated static let hasBootedSimulator: Bool = {
        simctl(["simctl", "list", "devices", "booted"])?.contains("(Booted)") ?? false
    }()

    /// The gate the deeplink suite actually needs: a booted simulator *with NotchDemo
    /// installed*.
    ///
    /// A booted simulator alone is not enough, and the difference is a red test rather than a
    /// skipped one. `simctl openurl` fails with OSStatus -10814 (application not found) when no
    /// installed app claims the scheme, which is exactly what the success-path test asserts
    /// against. Checking only "is something booted" therefore turned any machine with a
    /// simulator running but no demo app installed — the normal state of a fresh clone — into a
    /// failing suite. Build and install it first:
    ///
    ///     cd SampleApp
    ///     xcodebuild -project NotchDemo.xcodeproj -target NotchDemo -configuration Debug \
    ///                -sdk iphonesimulator build CODE_SIGNING_ALLOWED=NO
    ///     xcrun simctl install booted build/Debug-iphonesimulator/NotchDemo.app
    nonisolated static let hasNotchDemoInstalled: Bool = {
        guard hasBootedSimulator else { return false }
        return simctl(["simctl", "listapps", "booted"])?.contains(demoBundleID) ?? false
    }()

    /// One `xcrun` call, stdout as a string. Returns nil when the tool cannot be run at all.
    nonisolated private static func simctl(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // Read before waiting: `listapps` output is far larger than a pipe buffer, and waiting
        // first would deadlock against a full pipe.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
