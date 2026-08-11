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
    /// True when at least one simulator is booted; the bridge needs one to target. Computed
    /// once per process — spawning `simctl` per test would dominate the suite's runtime.
    nonisolated static let hasBootedSimulator: Bool = {
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
    }()
}
