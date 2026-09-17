//
//  DeviceWindowSelectionTests.swift
//  notchboardTests
//
//  Guards `chooseWindowIndex`, the unit-testable heart of both multi-window hazards. Android:
//  the emulator process owns several AX windows (device window, frameless Qt toolbar, extended
//  controls) and any of them can hold focus, so `.titled` must find the device window by title
//  wherever it sits. iOS: Device Hub (Xcode 27) owns a hub window, hidden tabs, full-width 33pt
//  strips and off-screen helpers alongside the device window, so `.focusedOrFirst` narrows to
//  on-screen, device-sized windows first — and must reproduce Simulator.app's plain
//  focused-else-first behaviour exactly whenever it has nothing to narrow by (vision.md §13.21).
//

import CoreGraphics
import Foundation
import Testing
@testable import notchboard

@Suite("Device window selection")
struct DeviceWindowSelectionTests {

    private let deviceTitle = "Android Emulator - Pixel_7_API_34:5554"

    /// Shorthand for the Simulator.app shape: no titles, no geometry, no window-server verdict.
    private func plain(_ count: Int) -> [WindowCandidate] {
        Array(repeating: WindowCandidate(), count: count)
    }

    private let deviceFrame = CGRect(x: 548, y: 115, width: 395, height: 860)
    private let hubFrame = CGRect(x: 100, y: 80, width: 1200, height: 900)
    private let stripFrame = CGRect(x: 0, y: 0, width: 1728, height: 33)
    private let helperFrame = CGRect(x: 0, y: 617, width: 500, height: 500)

    // MARK: - Android, by title

    /// The emulator's three-window shape with the device window at each position, focus
    /// parked on another window every time — focus must not matter.
    @Test("Titled selection finds the device window wherever it sits", arguments: 0...2)
    func titledFindsDeviceWindow(position: Int) {
        var candidates = [WindowCandidate(title: nil), WindowCandidate(title: "Extended Controls")]
        candidates.insert(WindowCandidate(title: deviceTitle), at: position)
        let focusedElsewhere = (position + 1) % candidates.count
        let chosen = DeviceWindowTracker.chooseWindowIndex(
            candidates: candidates, focusedIndex: focusedElsewhere, selection: .titled, kind: .androidEmulator
        )
        #expect(chosen == position)
    }

    @Test("Titled selection with no device window chooses nothing")
    func titledWithoutDeviceWindow() {
        let chosen = DeviceWindowTracker.chooseWindowIndex(
            candidates: [WindowCandidate(title: nil), WindowCandidate(title: "Extended Controls")],
            focusedIndex: 0, selection: .titled, kind: .androidEmulator
        )
        #expect(chosen == nil)
    }

    // MARK: - Simulator.app, focused-else-first unchanged

    @Test("FocusedOrFirst prefers the focused window")
    func focusedWins() {
        let chosen = DeviceWindowTracker.chooseWindowIndex(
            candidates: plain(3), focusedIndex: 2, selection: .focusedOrFirst, kind: .iosSimulator
        )
        #expect(chosen == 2)
    }

    @Test("FocusedOrFirst falls back to the first window when none is focused")
    func firstWhenUnfocused() {
        let chosen = DeviceWindowTracker.chooseWindowIndex(
            candidates: plain(2), focusedIndex: nil, selection: .focusedOrFirst, kind: .iosSimulator
        )
        #expect(chosen == 0)
    }

    @Test("No windows means no selection for either rule")
    func emptyWindows() {
        #expect(DeviceWindowTracker.chooseWindowIndex(
            candidates: [], focusedIndex: nil, selection: .focusedOrFirst, kind: .iosSimulator
        ) == nil)
        #expect(DeviceWindowTracker.chooseWindowIndex(
            candidates: [], focusedIndex: nil, selection: .titled, kind: .androidEmulator
        ) == nil)
    }

    // MARK: - Device Hub, narrowed by what is on screen

    @Test("An off-screen helper window is skipped in favour of the on-screen device window")
    func offscreenHelperSkipped() {
        let candidates = [
            WindowCandidate(frame: helperFrame, isOnscreen: false),
            WindowCandidate(frame: deviceFrame, isOnscreen: true),
        ]
        let chosen = DeviceWindowTracker.chooseWindowIndex(
            candidates: candidates, focusedIndex: nil, selection: .focusedOrFirst, kind: .iosSimulator
        )
        #expect(chosen == 1)
    }

    @Test("A hidden tab with the same frame as the visible one loses to the visible one")
    func hiddenTabSkipped() {
        let candidates = [
            WindowCandidate(frame: deviceFrame, isOnscreen: false), // the tab behind
            WindowCandidate(frame: deviceFrame, isOnscreen: true),
        ]
        let chosen = DeviceWindowTracker.chooseWindowIndex(
            candidates: candidates, focusedIndex: nil, selection: .focusedOrFirst, kind: .iosSimulator
        )
        #expect(chosen == 1)
    }

    @Test("Full-width strips are never device windows, even on screen and first")
    func stripsSkipped() {
        let candidates = [
            WindowCandidate(frame: stripFrame, isOnscreen: true),
            WindowCandidate(frame: stripFrame, isOnscreen: true),
            WindowCandidate(frame: deviceFrame, isOnscreen: true),
        ]
        let chosen = DeviceWindowTracker.chooseWindowIndex(
            candidates: candidates, focusedIndex: nil, selection: .focusedOrFirst, kind: .iosSimulator
        )
        #expect(chosen == 2)
    }

    @Test("Focus wins only when the focused window is itself dockable")
    func focusMustBeDockable() {
        let candidates = [
            WindowCandidate(frame: deviceFrame, isOnscreen: true),
            WindowCandidate(frame: helperFrame, isOnscreen: false),
        ]
        let focusedOffscreen = DeviceWindowTracker.chooseWindowIndex(
            candidates: candidates, focusedIndex: 1, selection: .focusedOrFirst, kind: .iosSimulator
        )
        #expect(focusedOffscreen == 0)
        let focusedDevice = DeviceWindowTracker.chooseWindowIndex(
            candidates: candidates, focusedIndex: 0, selection: .focusedOrFirst, kind: .iosSimulator
        )
        #expect(focusedDevice == 0)
    }

    @Test("With two dockable windows, focus decides between them")
    func focusDecidesAmongDockable() {
        let candidates = [
            WindowCandidate(frame: hubFrame, isOnscreen: true),
            WindowCandidate(frame: deviceFrame, isOnscreen: true),
        ]
        let chosen = DeviceWindowTracker.chooseWindowIndex(
            candidates: candidates, focusedIndex: 1, selection: .focusedOrFirst, kind: .iosSimulator
        )
        #expect(chosen == 1)
    }

    /// The host on another Space, or a window server that answered nothing: every window is
    /// off screen or unjudged, and the old rule must apply unchanged rather than choosing nothing.
    @Test("When nothing is dockable the plain focused-else-first rule applies")
    func fallbackWhenNothingDockable() {
        let allOffscreen = [
            WindowCandidate(frame: deviceFrame, isOnscreen: false),
            WindowCandidate(frame: deviceFrame, isOnscreen: false),
        ]
        #expect(DeviceWindowTracker.chooseWindowIndex(
            candidates: allOffscreen, focusedIndex: 1, selection: .focusedOrFirst, kind: .iosSimulator
        ) == 1)
        #expect(DeviceWindowTracker.chooseWindowIndex(
            candidates: allOffscreen, focusedIndex: nil, selection: .focusedOrFirst, kind: .iosSimulator
        ) == 0)
    }

    @Test("A window with geometry but no window-server verdict stays dockable")
    func unjudgedIsDockable() {
        #expect(DeviceWindowTracker.isDockable(WindowCandidate(frame: deviceFrame, isOnscreen: nil)))
        #expect(DeviceWindowTracker.isDockable(WindowCandidate()))
        #expect(!DeviceWindowTracker.isDockable(WindowCandidate(frame: stripFrame, isOnscreen: nil)))
        #expect(!DeviceWindowTracker.isDockable(WindowCandidate(frame: deviceFrame, isOnscreen: false)))
    }

    // MARK: - Matching AX frames to window-server bounds

    @Test("An AX frame matches its window-server bounds within rounding")
    func onscreenMatchTolerance() {
        let bounds = [stripFrame, deviceFrame]
        #expect(DeviceWindowTracker.isOnscreen(deviceFrame, among: bounds))
        #expect(DeviceWindowTracker.isOnscreen(deviceFrame.offsetBy(dx: 0.5, dy: -0.5), among: bounds))
        #expect(!DeviceWindowTracker.isOnscreen(deviceFrame.offsetBy(dx: 3, dy: 0), among: bounds))
        #expect(!DeviceWindowTracker.isOnscreen(hubFrame, among: bounds))
        #expect(!DeviceWindowTracker.isOnscreen(deviceFrame, among: []))
    }
}
