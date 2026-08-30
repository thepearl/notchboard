//
//  DockArbitrationTests.swift
//  notchboardTests
//
//  Guards the two pure routing rules that make dual-platform docking predictable: which
//  host window the panel docks to when a Simulator and an emulator are both on screen
//  (last activation wins, tie to iOS, sticky until the winner disappears), and which
//  bridge a fired deeplink goes through (the dock wins, else the sole running target,
//  else iOS).
//

import CoreGraphics
import Foundation
import Testing
@testable import notchboard

@Suite("Docking arbitration")
struct DockingArbitrationTests {

    private let frame = CGRect(x: 0, y: 0, width: 400, height: 800)
    private let earlier = Date(timeIntervalSinceReferenceDate: 100)
    private let later = Date(timeIntervalSinceReferenceDate: 200)

    @Test("No windows anywhere docks nothing")
    func nothingRunning() {
        #expect(AppDelegate.dockedKind(
            simulatorFrame: nil, simulatorActivatedAt: later,
            emulatorFrame: nil, emulatorActivatedAt: earlier
        ) == nil)
    }

    @Test("A lone host wins regardless of activation stamps")
    func loneHostWins() {
        #expect(AppDelegate.dockedKind(
            simulatorFrame: frame, simulatorActivatedAt: nil,
            emulatorFrame: nil, emulatorActivatedAt: later
        ) == .iosSimulator)
        #expect(AppDelegate.dockedKind(
            simulatorFrame: nil, simulatorActivatedAt: later,
            emulatorFrame: frame, emulatorActivatedAt: nil
        ) == .androidEmulator)
    }

    @Test("With both on screen, the most recently activated host wins")
    func lastActivationWins() {
        #expect(AppDelegate.dockedKind(
            simulatorFrame: frame, simulatorActivatedAt: earlier,
            emulatorFrame: frame, emulatorActivatedAt: later
        ) == .androidEmulator)
        #expect(AppDelegate.dockedKind(
            simulatorFrame: frame, simulatorActivatedAt: later,
            emulatorFrame: frame, emulatorActivatedAt: earlier
        ) == .iosSimulator)
    }

    @Test("A never-activated host counts as distant past; a full tie goes to iOS")
    func tieBreaks() {
        #expect(AppDelegate.dockedKind(
            simulatorFrame: frame, simulatorActivatedAt: nil,
            emulatorFrame: frame, emulatorActivatedAt: earlier
        ) == .androidEmulator)
        #expect(AppDelegate.dockedKind(
            simulatorFrame: frame, simulatorActivatedAt: nil,
            emulatorFrame: frame, emulatorActivatedAt: nil
        ) == .iosSimulator)
        #expect(AppDelegate.dockedKind(
            simulatorFrame: frame, simulatorActivatedAt: earlier,
            emulatorFrame: frame, emulatorActivatedAt: earlier
        ) == .iosSimulator)
    }
}

@Suite("Deeplink target routing")
struct DeeplinkTargetTests {

    @Test("The docked device always wins")
    func dockWins() {
        #expect(AppDelegate.deeplinkTarget(docked: .androidEmulator, iosRunning: true, androidRunning: true)
            == .androidEmulator)
        #expect(AppDelegate.deeplinkTarget(docked: .iosSimulator, iosRunning: false, androidRunning: true)
            == .iosSimulator)
    }

    @Test("Undocked, the sole running target gets the login")
    func soleRunnerWins() {
        #expect(AppDelegate.deeplinkTarget(docked: nil, iosRunning: false, androidRunning: true)
            == .androidEmulator)
        #expect(AppDelegate.deeplinkTarget(docked: nil, iosRunning: true, androidRunning: false)
            == .iosSimulator)
    }

    @Test("Undocked with both — or neither — running defaults to iOS")
    func ambiguityDefaultsToIOS() {
        #expect(AppDelegate.deeplinkTarget(docked: nil, iosRunning: true, androidRunning: true)
            == .iosSimulator)
        #expect(AppDelegate.deeplinkTarget(docked: nil, iosRunning: false, androidRunning: false)
            == .iosSimulator)
    }
}
