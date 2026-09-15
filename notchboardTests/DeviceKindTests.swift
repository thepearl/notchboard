//
//  DeviceKindTests.swift
//  notchboardTests
//
//  Guards the pure identity rules for both hosts. iOS: the two bundle ids that are both live
//  today — Simulator.app up to Xcode 26 and Device Hub from Xcode 27 (vision.md §13.21) — so a
//  Mac on either Xcode docks and a new Xcode cannot silently unhost the panel again. Android:
//  the qemu executable-name predicate, and the anchored device-window title parse that both
//  selects the window and yields the console port joining it to its adb serial. If either
//  platform ever changes these facts, these fixtures are the single place they live.
//

import Foundation
import Testing
@testable import notchboard

@Suite("Device kind identity")
struct DeviceKindTests {

    @Test("Both iOS host bundle ids match", arguments: [
        "com.apple.iphonesimulator", // Simulator.app, Xcode ≤ 26
        "com.apple.dt.Devices",      // DeviceHub.app, Xcode 27+
    ])
    func simulatorBundleIDsMatch(bundleID: String) {
        #expect(DeviceKind.matchesSimulatorBundleID(bundleID))
        #expect(DeviceKind.simulatorBundleIDs.contains(bundleID))
    }

    @Test("Other Xcode-family and unrelated bundle ids never match", arguments: [
        "com.apple.dt.Xcode",
        "com.apple.dt.DevicesSystemUpdater", // Device Hub's nested helper app
        "com.apple.CoreSimulator.SimRenderingServices.SimRenderServer",
        "com.google.android.studio",
        "flourix.notchboard",
        "",
    ])
    func otherBundleIDsRejected(bundleID: String) {
        #expect(!DeviceKind.matchesSimulatorBundleID(bundleID))
    }

    @Test("A missing bundle id is never the iOS host")
    func nilBundleIDRejected() {
        #expect(!DeviceKind.matchesSimulatorBundleID(nil))
    }

    @Test("Real qemu executable names match", arguments: [
        "qemu-system-aarch64", "qemu-system-x86_64", "qemu-system-aarch64-headless",
    ])
    func qemuNamesMatch(name: String) {
        #expect(DeviceKind.matchesEmulatorExecutableName(name))
    }

    @Test("Other executables never match", arguments: [
        "Simulator", "DeviceHub", "emulator", "qemu-img", "studio", "notqemu-system-aarch64", "",
    ])
    func otherNamesRejected(name: String) {
        #expect(!DeviceKind.matchesEmulatorExecutableName(name))
    }

    @Test("The device-window title yields its console port")
    func titleYieldsPort() {
        #expect(DeviceKind.consolePort(fromTitle: "Android Emulator - Pixel_7_API_34:5554") == 5554)
        #expect(DeviceKind.consolePort(fromTitle: "Android Emulator - a:5556") == 5556)
    }

    @Test("Non-device-window titles parse to nothing", arguments: [
        "Extended Controls",
        "Android Emulator - Pixel_7_API_34", // no port
        "Android Emulator - :5554",          // no AVD name
        "Android Emulator - Pixel:5554 ",    // trailing junk — the anchor is load-bearing
        "prefix Android Emulator - Pixel:5554",
        "Android Emulator - Pixel:port",
        "",
    ])
    func badTitlesRejected(title: String) {
        #expect(DeviceKind.consolePort(fromTitle: title) == nil)
        #expect(!DeviceKind.androidEmulator.matchesDeviceWindowTitle(title))
    }

    @Test("A missing title parses to nothing")
    func nilTitleRejected() {
        #expect(DeviceKind.consolePort(fromTitle: nil) == nil)
        #expect(!DeviceKind.androidEmulator.matchesDeviceWindowTitle(nil))
    }

    @Test("The Simulator never selects by title")
    func simulatorIgnoresTitles() {
        #expect(!DeviceKind.iosSimulator.matchesDeviceWindowTitle("Android Emulator - Pixel:5554"))
        #expect(DeviceKind.iosSimulator.windowSelection == .focusedOrFirst)
        #expect(DeviceKind.androidEmulator.windowSelection == .titled)
    }
}
