//
//  DeviceKind.swift
//  notchboard
//
//  Identity of the dockable device hosts: which running process is an iOS Simulator or an
//  Android emulator. The Simulator is a normal .app with a bundle id. The standalone
//  Android emulator is a bare qemu Mach-O inside the SDK (`qemu-system-*`), so its
//  `NSRunningApplication.bundleIdentifier` is nil and the executable name is the only
//  stable identity — the same rule AltTab ships for it. The Android facts are researched,
//  not yet verified against a live AVD, so everything AX-adjacent here stays a pure
//  function over plain values: a surprise changes one function, not the tracker design.
//

import AppKit

/// How to pick the device window among the AX windows a host process owns.
enum WindowSelection: Sendable {
    /// The app's focused window, else its first — the Simulator shape, where any window
    /// is a device window.
    case focusedOrFirst
    /// The first window whose title identifies a device window. The emulator process owns
    /// several AX windows (device window, frameless Qt toolbar, extended controls), and
    /// focus proves nothing — the toolbar or extended controls can hold it.
    case titled
}

enum DeviceKind: Sendable, CaseIterable {
    case iosSimulator
    case androidEmulator

    /// Bundle identifier of the real iOS Simulator app.
    static let simulatorBundleID = "com.apple.iphonesimulator"

    /// Whether this running application is this kind of device host.
    func matches(_ app: NSRunningApplication) -> Bool {
        switch self {
        case .iosSimulator:
            return app.bundleIdentifier == Self.simulatorBundleID
        case .androidEmulator:
            // The nil check is load-bearing: a future .app wrapper shipping a qemu-named
            // helper must not be claimed, and every real .app has a bundle id.
            guard app.bundleIdentifier == nil, let executable = app.executableURL else { return false }
            return Self.matchesEmulatorExecutableName(executable.lastPathComponent)
        }
    }

    /// The executable-name half of the Android match (e.g. `qemu-system-aarch64`),
    /// separated so tests never need a real process.
    nonisolated static func matchesEmulatorExecutableName(_ name: String) -> Bool {
        name.hasPrefix("qemu-system")
    }

    nonisolated var windowSelection: WindowSelection {
        switch self {
        case .iosSimulator: return .focusedOrFirst
        case .androidEmulator: return .titled
        }
    }

    /// Whether an AX window title identifies this kind's device window. Only consulted
    /// for kinds that select `.titled`; the Simulator never matches by title.
    nonisolated func matchesDeviceWindowTitle(_ title: String?) -> Bool {
        switch self {
        case .iosSimulator: return false
        case .androidEmulator: return Self.consolePort(fromTitle: title) != nil
        }
    }

    /// Parses the console port out of an emulator device-window title, which is exactly
    /// `Android Emulator - <avd>:<console_port>` (verified in the emulator source; AVD
    /// names cannot contain spaces or colons). Anchored on both ends so a parse failure
    /// means "not the device window", never a guess at the wrong one. The port is the
    /// join key to the adb serial `emulator-<port>`.
    nonisolated static func consolePort(fromTitle title: String?) -> Int? {
        guard let title,
              let match = title.wholeMatch(of: #/Android Emulator - .+:([0-9]+)/#) else { return nil }
        return Int(match.1)
    }
}
