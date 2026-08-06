//
//  GlobalHotKeyTests.swift
//  notchboardTests
//
//  Covers the hot-key modifier mapping and its persistence. The Carbon registration itself
//  is a system-level side effect that a unit test can't meaningfully assert (registering a
//  chord in a test process would claim it machine-wide for the duration), so that half is
//  verified by the runtime smoke check instead.
//

import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import notchboard

@Suite("Hot-key modifier mapping")
struct HotKeyModifierTests {

    @Test("Carbon flags match the Carbon constants")
    func carbonFlags() {
        #expect(NBHotKeyModifier.control.carbonFlags == UInt32(controlKey))
        #expect(NBHotKeyModifier.command.carbonFlags == UInt32(cmdKey))
        #expect(NBHotKeyModifier.optionCommand.carbonFlags == UInt32(optionKey | cmdKey))
    }

    @Test("AppKit flags mirror the Carbon flags, so the in-panel monitor matches the global chord")
    func appKitFlagsMirrorCarbon() {
        #expect(NBHotKeyModifier.control.appKitFlags == .control)
        #expect(NBHotKeyModifier.command.appKitFlags == .command)
        #expect(NBHotKeyModifier.optionCommand.appKitFlags == [.option, .command])
    }

    @Test("Every modifier carries a distinct symbol prefix and a cost note")
    func uiCopyIsComplete() {
        let prefixes = NBHotKeyModifier.allCases.map(\.symbolPrefix)
        #expect(Set(prefixes).count == NBHotKeyModifier.allCases.count)
        for modifier in NBHotKeyModifier.allCases {
            #expect(!modifier.label.isEmpty)
            #expect(!modifier.costNote.isEmpty)
        }
    }

    @Test("Combos use the K and N virtual key codes")
    func comboKeyCodes() {
        #expect(GlobalHotKeys.Combo.search(modifier: .control).keyCode == UInt32(kVK_ANSI_K))
        #expect(GlobalHotKeys.Combo.newElement(modifier: .control).keyCode == UInt32(kVK_ANSI_N))
        // The modifier must reach the combo, not be dropped on the way.
        #expect(GlobalHotKeys.Combo.search(modifier: .command).carbonModifiers == UInt32(cmdKey))
    }
}

/// Exercises the real Carbon path. Registration is process-global, so these claim the chords
/// for the fraction of a second the test runs and release them immediately — serialized so
/// two of them can't overlap.
@Suite("Carbon registration", .serialized)
struct CarbonRegistrationTests {

    @Test("The window server accepts the K and N chords", arguments: NBHotKeyModifier.allCases)
    func registrationSucceeds(modifier: NBHotKeyModifier) {
        let hotKeys = GlobalHotKeys()
        hotKeys.setCombos([
            (combo: .search(modifier: modifier), handler: {}),
            (combo: .newElement(modifier: modifier), handler: {}),
        ])
        #expect(hotKeys.registeredComboCount == 0, "must not claim anything before being enabled")

        hotKeys.setEnabled(true)
        #expect(
            hotKeys.registeredComboCount == 2,
            "RegisterEventHotKey rejected \(modifier.symbolPrefix)K/\(modifier.symbolPrefix)N on this OS"
        )

        hotKeys.setEnabled(false)
        #expect(hotKeys.registeredComboCount == 0, "chords must be handed back on release")
    }

    @Test("Changing the combos while enabled re-registers in place")
    func recombineWhileEnabled() {
        let hotKeys = GlobalHotKeys()
        hotKeys.setCombos([(combo: .search(modifier: .control), handler: {})])
        hotKeys.setEnabled(true)
        #expect(hotKeys.registeredComboCount == 1)

        hotKeys.setCombos([
            (combo: .search(modifier: .optionCommand), handler: {}),
            (combo: .newElement(modifier: .optionCommand), handler: {}),
        ])
        #expect(hotKeys.registeredComboCount == 2, "new combos should be live immediately")

        hotKeys.setEnabled(false)
        #expect(hotKeys.registeredComboCount == 0)
    }

    @Test("Enabling twice does not double-register")
    func idempotentEnable() {
        let hotKeys = GlobalHotKeys()
        hotKeys.setCombos([(combo: .newElement(modifier: .optionCommand), handler: {})])
        hotKeys.setEnabled(true)
        hotKeys.setEnabled(true)
        #expect(hotKeys.registeredComboCount == 1)
        hotKeys.setEnabled(false)
    }
}

@Suite("Hot-key setting persistence")
struct HotKeyPersistenceTests {

    @Test("The chosen modifier round-trips through persisted state")
    func roundTrip() {
        let vm = NotchboardViewModel()
        vm.hotKeyModifier = .optionCommand
        let state = vm.persistableState(onboardingCompleted: true, onboardingName: "n")

        let restored = NotchboardViewModel()
        restored.restore(from: state)
        #expect(restored.hotKeyModifier == .optionCommand)
    }

    @Test("A state file predating the setting defaults to Control")
    func lenientDecodeDefaultsToControl() throws {
        let vm = NotchboardViewModel()
        vm.hotKeyModifier = .command
        let state = vm.persistableState(onboardingCompleted: true, onboardingName: "n")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        json.removeValue(forKey: "hotKeyModifier")

        let decoded = try JSONDecoder().decode(
            PersistedAppState.self,
            from: JSONSerialization.data(withJSONObject: json)
        )
        #expect(decoded.hotKeyModifier == .control)
    }

    @Test("Default is Control, so a fresh install doesn't claim Xcode's ⌘N")
    func defaultAvoidsCommandN() {
        #expect(NotchboardViewModel().hotKeyModifier == .control)
    }
}
