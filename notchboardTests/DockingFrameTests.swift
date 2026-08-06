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
        let frame = AppDelegate.dockedFrame(simFrame: simFrame, size: size, edge: .right, clampedTo: screen)
        #expect(frame.minX == simFrame.maxX)
        #expect(frame.midY == simFrame.midY)
    }

    @Test("Left dock sits flush against the Simulator's left edge")
    func leftDock() {
        let frame = AppDelegate.dockedFrame(simFrame: simFrame, size: size, edge: .left, clampedTo: screen)
        #expect(frame.maxX == simFrame.minX)
        #expect(frame.midY == simFrame.midY)
    }

    @Test("Simulator flush against the right screen edge keeps the panel on screen")
    func clampAtRightEdge() {
        let flushSim = NSRect(x: 1600, y: 0, width: 400, height: 1200) // maxX == screen maxX
        let frame = AppDelegate.dockedFrame(simFrame: flushSim, size: size, edge: .right, clampedTo: screen)
        #expect(frame.maxX <= screen.maxX)
        #expect(frame.minX >= screen.minX)
    }

    @Test("Simulator flush against the left screen edge keeps the panel on screen")
    func clampAtLeftEdge() {
        let flushSim = NSRect(x: 0, y: 0, width: 400, height: 1200)
        let frame = AppDelegate.dockedFrame(simFrame: flushSim, size: size, edge: .left, clampedTo: screen)
        #expect(frame.minX >= screen.minX)
    }

    @Test("Vertical clamp keeps a tall panel on screen for a Simulator near the screen top")
    func clampVertically() {
        let highSim = NSRect(x: 500, y: 1150, width: 400, height: 800) // extends above the screen
        let frame = AppDelegate.dockedFrame(simFrame: highSim, size: size, edge: .right, clampedTo: screen)
        #expect(frame.maxY <= screen.maxY)
        #expect(frame.minY >= screen.minY)
    }

    @Test("No clamp rectangle leaves the raw docked frame untouched")
    func noClamp() {
        let frame = AppDelegate.dockedFrame(simFrame: simFrame, size: size, edge: .right, clampedTo: nil)
        #expect(frame.minX == simFrame.maxX)
    }
}
