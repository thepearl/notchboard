//
//  DeviceKindTests.swift
//  notchboardTests
//
//  Guards the pure identity rules for the Android emulator, which are researched but not
//  yet verified against a live AVD: the qemu executable-name predicate, and the anchored
//  device-window title parse that both selects the window and yields the console port
//  joining it to its adb serial. If the emulator ever changes either, these fixtures are
//  the single place the facts live.
//

import Foundation
import Testing
@testable import notchboard

@Suite("Device kind identity")
struct DeviceKindTests {

    @Test("Real qemu executable names match", arguments: [
        "qemu-system-aarch64", "qemu-system-x86_64", "qemu-system-aarch64-headless",
    ])
    func qemuNamesMatch(name: String) {
        #expect(DeviceKind.matchesEmulatorExecutableName(name))
    }

    @Test("Other executables never match", arguments: [
        "Simulator", "emulator", "qemu-img", "studio", "notqemu-system-aarch64", "",
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
