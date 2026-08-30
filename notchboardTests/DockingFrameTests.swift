//
//  DockingFrameTests.swift
//  notchboardTests
//
//  Pure-maths coverage of the docked panel frame: edge selection, vertical centring,
//  and the screen clamp that keeps the panel reachable when Simulator hugs the screen
//  edge (zoomed/fullscreen), where it previously landed entirely offscreen.
//

import CoreGraphics
import Foundation
import Testing
@testable import notchboard

@Suite("Docked frame maths")
struct DockedFrameTests {

    private let simFrame = NSRect(x: 500, y: 200, width: 400, height: 800)
    private let size = CGSize(width: 28, height: 148)
    private let screen = NSRect(x: 0, y: 0, width: 2000, height: 1200)

    @Test("Right dock sits flush against the Simulator's right edge, vertically centred")
    func rightDock() {
        let frame = AppDelegate.dockedFrame(hostFrame: simFrame, size: size, edge: .right, clampedTo: screen)
        #expect(frame.minX == simFrame.maxX)
        #expect(frame.midY == simFrame.midY)
    }

    @Test("Left dock sits flush against the Simulator's left edge")
    func leftDock() {
        let frame = AppDelegate.dockedFrame(hostFrame: simFrame, size: size, edge: .left, clampedTo: screen)
        #expect(frame.maxX == simFrame.minX)
        #expect(frame.midY == simFrame.midY)
    }

    @Test("Simulator flush against the right screen edge keeps the panel on screen")
    func clampAtRightEdge() {
        let flushSim = NSRect(x: 1600, y: 0, width: 400, height: 1200) // maxX == screen maxX
        let frame = AppDelegate.dockedFrame(hostFrame: flushSim, size: size, edge: .right, clampedTo: screen)
        #expect(frame.maxX <= screen.maxX)
        #expect(frame.minX >= screen.minX)
    }

    @Test("Simulator flush against the left screen edge keeps the panel on screen")
    func clampAtLeftEdge() {
        let flushSim = NSRect(x: 0, y: 0, width: 400, height: 1200)
        let frame = AppDelegate.dockedFrame(hostFrame: flushSim, size: size, edge: .left, clampedTo: screen)
        #expect(frame.minX >= screen.minX)
    }

    @Test("Vertical clamp keeps a tall panel on screen for a Simulator near the screen top")
    func clampVertically() {
        let highSim = NSRect(x: 500, y: 1150, width: 400, height: 800) // extends above the screen
        let frame = AppDelegate.dockedFrame(hostFrame: highSim, size: size, edge: .right, clampedTo: screen)
        #expect(frame.maxY <= screen.maxY)
        #expect(frame.minY >= screen.minY)
    }

    @Test("No clamp rectangle leaves the raw docked frame untouched")
    func noClamp() {
        let frame = AppDelegate.dockedFrame(hostFrame: simFrame, size: size, edge: .right, clampedTo: nil)
        #expect(frame.minX == simFrame.maxX)
    }
}

/// The emulator's Qt toolbar hangs a fixed control stack down the window's right flank,
/// and the centre-placed notch parked itself on top of the nav buttons on the first
/// live-AVD run. These pin the clearance rule: grow the offset only when the toolbar
/// would collide, never for the Simulator, never on the left edge.
@Suite("Collapsed notch offset")
struct CollapsedNotchOffsetTests {

    private let notchHeight: CGFloat = 62

    @Test("The Simulator keeps the standard nudge on both edges")
    func simulatorStandardOffset() {
        #expect(AppDelegate.collapsedNotchOffset(
            kind: .iosSimulator, edge: .right, hostHeight: 824, notchHeight: notchHeight
        ) == AppDelegate.notchVerticalOffset)
        #expect(AppDelegate.collapsedNotchOffset(
            kind: .iosSimulator, edge: .left, hostHeight: 824, notchHeight: notchHeight
        ) == AppDelegate.notchVerticalOffset)
    }

    @Test("A left-docked emulator has no toolbar to dodge")
    func emulatorLeftStandardOffset() {
        #expect(AppDelegate.collapsedNotchOffset(
            kind: .androidEmulator, edge: .left, hostHeight: 824, notchHeight: notchHeight
        ) == AppDelegate.notchVerticalOffset)
    }

    @Test("A right-docked emulator notch's top lands just below the toolbar stack")
    func emulatorRightClearsToolbar() {
        let hostHeight: CGFloat = 824 // the Pixel-sized window the overlap was measured on
        let offset = AppDelegate.collapsedNotchOffset(
            kind: .androidEmulator, edge: .right, hostHeight: hostHeight, notchHeight: notchHeight
        )
        let topFromWindowTop = hostHeight / 2 + offset - notchHeight / 2
        #expect(topFromWindowTop == AppDelegate.emulatorToolbarClearance)
    }

    @Test("A window tall enough to clear the toolbar at centre keeps the standard nudge")
    func tallEmulatorWindowStaysNearCentre() {
        #expect(AppDelegate.collapsedNotchOffset(
            kind: .androidEmulator, edge: .right, hostHeight: 1200, notchHeight: notchHeight
        ) == AppDelegate.notchVerticalOffset)
    }

    @Test("The coach-mark's taller collapsed size still tops out below the toolbar")
    func coachMarkHeightStillClears() {
        let hostHeight: CGFloat = 824
        let coachMarkHeight: CGFloat = 122
        let offset = AppDelegate.collapsedNotchOffset(
            kind: .androidEmulator, edge: .right, hostHeight: hostHeight, notchHeight: coachMarkHeight
        )
        #expect(hostHeight / 2 + offset - coachMarkHeight / 2 == AppDelegate.emulatorToolbarClearance)
    }
}
