//
//  DeviceWindowSelectionTests.swift
//  notchboardTests
//
//  Guards `chooseWindowIndex`, the unit-testable heart of the Android docking hazard: the
//  emulator process owns several AX windows (device window, frameless Qt toolbar, extended
//  controls) and any of them can hold focus, so `.titled` must find the device window by
//  title wherever it sits — and `.focusedOrFirst` must keep reproducing the Simulator's
//  focused-else-first behaviour exactly.
//

import Foundation
import Testing
@testable import notchboard

@Suite("Device window selection")
struct DeviceWindowSelectionTests {

    private let deviceTitle = "Android Emulator - Pixel_7_API_34:5554"

    /// The emulator's three-window shape with the device window at each position, focus
    /// parked on another window every time — focus must not matter.
    @Test("Titled selection finds the device window wherever it sits", arguments: 0...2)
    func titledFindsDeviceWindow(position: Int) {
        var titles: [String?] = [nil, "Extended Controls"] // Qt toolbar windows are untitled
        titles.insert(deviceTitle, at: position)
        let focusedElsewhere = (position + 1) % titles.count
        let chosen = DeviceWindowTracker.chooseWindowIndex(
            titles: titles, focusedIndex: focusedElsewhere, selection: .titled, kind: .androidEmulator
        )
        #expect(chosen == position)
    }

    @Test("Titled selection with no device window chooses nothing")
    func titledWithoutDeviceWindow() {
        let chosen = DeviceWindowTracker.chooseWindowIndex(
            titles: [nil, "Extended Controls"], focusedIndex: 0, selection: .titled, kind: .androidEmulator
        )
        #expect(chosen == nil)
    }

    @Test("FocusedOrFirst prefers the focused window")
    func focusedWins() {
        let chosen = DeviceWindowTracker.chooseWindowIndex(
            titles: [nil, nil, nil], focusedIndex: 2, selection: .focusedOrFirst, kind: .iosSimulator
        )
        #expect(chosen == 2)
    }

    @Test("FocusedOrFirst falls back to the first window when none is focused")
    func firstWhenUnfocused() {
        let chosen = DeviceWindowTracker.chooseWindowIndex(
            titles: [nil, nil], focusedIndex: nil, selection: .focusedOrFirst, kind: .iosSimulator
        )
        #expect(chosen == 0)
    }

    @Test("No windows means no selection for either rule")
    func emptyWindows() {
        #expect(DeviceWindowTracker.chooseWindowIndex(
            titles: [], focusedIndex: nil, selection: .focusedOrFirst, kind: .iosSimulator
        ) == nil)
        #expect(DeviceWindowTracker.chooseWindowIndex(
            titles: [], focusedIndex: nil, selection: .titled, kind: .androidEmulator
        ) == nil)
    }
}
