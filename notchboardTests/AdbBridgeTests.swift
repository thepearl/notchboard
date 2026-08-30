//
//  AdbBridgeTests.swift
//  notchboardTests
//
//  Guards AdbBridge's three pure functions. The quoting test is the one that matters
//  most: `adb shell` hands its re-joined arguments to the device-side `sh`, so an
//  unquoted `&` truncates the login intent at `user=…` — a bug that only manifests as
//  "the app opened but nobody logged in". The classify fixtures pin down adb's habit of
//  exiting 0 while printing the actual failure to stdout.
//

import Foundation
import Testing
@testable import notchboard

@Suite("adb device-shell quoting")
struct AdbQuotingTests {

    @Test("The query's & survives the device-side sh re-parse")
    func ampersandSurvives() {
        let url = "notchdemo://debug/login?user=alice&pass=hunter2"
        #expect(AdbBridge.deviceShellQuoted(url) == "'notchdemo://debug/login?user=alice&pass=hunter2'")
    }

    @Test("An embedded single quote closes, escapes and reopens")
    func embeddedQuoteEscapes() {
        #expect(AdbBridge.deviceShellQuoted("a'b") == #"'a'\''b'"#)
    }

    @Test("A quote-free URL is simply wrapped")
    func plainWrap() {
        #expect(AdbBridge.deviceShellQuoted("x://y") == "'x://y'")
    }
}

@Suite("adb discovery order")
struct AdbDiscoveryTests {

    private let home = "/Users/dev"

    private func resolve(env: [String: String], existing: Set<String>) -> String? {
        AdbBridge.resolveAdb(env: env, homeDirectory: home, fileExists: { existing.contains($0) })
    }

    @Test("ANDROID_HOME wins over everything")
    func androidHomeWins() {
        let path = resolve(
            env: ["ANDROID_HOME": "/sdk-a", "ANDROID_SDK_ROOT": "/sdk-b"],
            existing: ["/sdk-a/platform-tools/adb", "/sdk-b/platform-tools/adb", "/opt/homebrew/bin/adb"]
        )
        #expect(path == "/sdk-a/platform-tools/adb")
    }

    @Test("ANDROID_SDK_ROOT beats the default SDK path")
    func sdkRootBeatsDefault() {
        let path = resolve(
            env: ["ANDROID_SDK_ROOT": "/sdk-b"],
            existing: ["/sdk-b/platform-tools/adb", "\(home)/Library/Android/sdk/platform-tools/adb"]
        )
        #expect(path == "/sdk-b/platform-tools/adb")
    }

    @Test("The default Android Studio SDK path beats Homebrew")
    func defaultSDKBeatsHomebrew() {
        let path = resolve(
            env: [:],
            existing: ["\(home)/Library/Android/sdk/platform-tools/adb", "/opt/homebrew/bin/adb"]
        )
        #expect(path == "\(home)/Library/Android/sdk/platform-tools/adb")
    }

    @Test("A set env var pointing at nothing is skipped, not trusted")
    func missingEnvPathSkipped() {
        let path = resolve(
            env: ["ANDROID_HOME": "/sdk-gone"],
            existing: ["/opt/homebrew/bin/adb"]
        )
        #expect(path == "/opt/homebrew/bin/adb")
    }

    @Test("Homebrew beats /usr/local; nothing anywhere is nil")
    func tailOrder() {
        #expect(resolve(env: [:], existing: ["/opt/homebrew/bin/adb", "/usr/local/bin/adb"]) == "/opt/homebrew/bin/adb")
        #expect(resolve(env: [:], existing: ["/usr/local/bin/adb"]) == "/usr/local/bin/adb")
        #expect(resolve(env: [:], existing: []) == nil)
    }
}

@Suite("adb outcome classification")
struct AdbClassifyTests {

    @Test("A clean exit with quiet streams is success")
    func cleanSuccess() {
        #expect(AdbBridge.classify(exitStatus: 0, stdout: "Starting: Intent { act=android.intent.action.VIEW dat=notchdemo://debug/... }", stderr: "") == nil)
    }

    @Test("Exit 0 with an Error line on stdout is still a failure — adb's signature habit")
    func exitZeroErrorLine() {
        let stdout = """
        Starting: Intent { act=android.intent.action.VIEW dat=notchdemo://debug/... }
        Error: Activity not started, unable to resolve Intent { act=android.intent.action.VIEW dat=notchdemo://debug/... flg=0x10000000 }
        """
        let failure = AdbBridge.classify(exitStatus: 0, stdout: stdout, stderr: "")
        guard case .failed(let detail)? = failure else {
            Issue.record("expected .failed, got \(String(describing: failure))")
            return
        }
        #expect(detail.hasPrefix("Error: Activity not started"))
        #expect(detail.count <= 120)
    }

    @Test("No device connected maps to device-not-available", arguments: [
        "adb: no devices/emulators found",
        "adb: device 'emulator-9999' not found",
    ])
    func noDevice(stderr: String) {
        #expect(AdbBridge.classify(exitStatus: 1, stdout: "", stderr: stderr)
            == .deviceNotAvailable(.androidEmulator))
    }

    @Test("Any other non-zero exit carries the stderr prefix")
    func genericFailure() {
        let failure = AdbBridge.classify(exitStatus: 1, stdout: "", stderr: "adb: something else broke")
        #expect(failure == .failed("adb: something else broke"))
    }

    @Test("A silent non-zero exit still names the exit code")
    func silentFailure() {
        #expect(AdbBridge.classify(exitStatus: 137, stdout: "", stderr: "") == .failed("exit 137"))
    }
}
