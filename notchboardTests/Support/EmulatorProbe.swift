//
//  EmulatorProbe.swift
//  notchboardTests
//
//  The skip gate for the suite that needs a running Android emulator to fire a deeplink
//  into — the adb twin of SimulatorProbe, same shape for the same mechanical reason: a
//  `.enabled(if:)` suite trait cannot reach a private static of the type it annotates.
//
//  adb is resolved through AdbBridge's own discovery order, so the gate can never pass
//  while the bridge under test would fail to find the tool.
//

import Foundation
@testable import notchboard

enum EmulatorProbe {
    /// The Android sample app that registers the `notchdemo://` scheme.
    /// SampleApp/NotchDemoAndroid sets this as its applicationId.
    private static let demoPackage = "com.flourix.notchdemo"

    /// True when at least one emulator is attached and ready (`adb devices` reports an
    /// `emulator-<port>` serial in the `device` state — not `offline`, not a physical
    /// phone). Computed once per process, like the other probes.
    nonisolated static let hasRunningEmulator: Bool = {
        guard let adbPath = AdbBridge.adbPath,
              let output = adb(adbPath, ["devices"]) else { return false }
        return output
            .components(separatedBy: .newlines)
            .contains { $0.wholeMatch(of: #/emulator-[0-9]+\tdevice/#) != nil }
    }()

    /// The gate the success-path test actually needs: an emulator *with NotchDemoAndroid
    /// installed*. Without it, `am start` reports "Error: Activity not started" — which is
    /// exactly what the failure-path test asserts against, so gating on the emulator alone
    /// would turn a fresh clone's run red rather than skipped (the same trap SimulatorProbe
    /// documents). Build and install it first — see SampleApp/NotchDemoAndroid/README.md.
    nonisolated static let hasNotchDemoInstalled: Bool = {
        guard hasRunningEmulator, let adbPath = AdbBridge.adbPath else { return false }
        // `--user current` is load-bearing: without it, `pm resolve-activity` on API 35
        // resolves against no user at all and reports "No activity found" even when the
        // app is installed — a false negative that silently skips the success-path test.
        let output = adb(adbPath, [
            "shell", "pm", "resolve-activity", "--user", "current",
            "-a", "android.intent.action.VIEW", "-d", "notchdemo://debug/login",
        ])
        return output?.contains(demoPackage) ?? false
    }()

    /// One adb call, stdout as a string. Returns nil when the tool cannot be run at all.
    nonisolated private static func adb(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // Read before waiting, or a full pipe deadlocks the child (see SimulatorProbe).
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
