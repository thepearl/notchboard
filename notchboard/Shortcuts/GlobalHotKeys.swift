//
//  GlobalHotKeys.swift
//  notchboard
//
//  Globally-registered keyboard shortcuts that are genuinely *consumed*: while registered,
//  the frontmost app never sees the keystroke.
//
//  This uses Carbon's `RegisterEventHotKey`, which is what every comparable macOS utility
//  uses — soffes/HotKey and sindresorhus/KeyboardShortcuts (the two libraries most menu-bar
//  apps depend on) are both wrappers around it, as are Maccy and Ice. It is old C API but
//  still the only supported way to claim a chord system-wide. The alternative Notchboard
//  used before, `NSEvent.addGlobalMonitorForEvents`, is observe-only: its handler returns
//  Void because macOS deliberately never lets a background app swallow another app's
//  keystrokes. That meant a plain ⌘N fired Xcode's New File *and* Notchboard at once.
//
//  The flip side of consuming a chord is that Notchboard owns it: while ⌃N is registered,
//  nothing else on the system can receive ⌃N. So registration is deliberately *scoped* —
//  `setEnabled(false)` hands the chord straight back to the rest of the system, and
//  AppDelegate keeps it registered only while the panel is actually there to respond (see
//  `syncHotKeyRegistration`). Notchboard claims the shortcut when it can act on it, and not
//  a moment longer.
//
//  Unlike an event tap (`CGEventTap`), this needs no Accessibility or Input Monitoring
//  permission of its own — the chord is registered with the window server rather than the
//  app snooping the event stream.
//

import AppKit
import Carbon.HIToolbox
import os

@MainActor
final class GlobalHotKeys {
    /// One chord: a virtual key code plus Carbon modifier flags.
    struct Combo: Equatable {
        let keyCode: UInt32
        let carbonModifiers: UInt32
    }

    private static let logger = Logger(subsystem: "flourix.notchboard", category: "hotkeys")

    /// Four-char signature identifying our hot keys in the shared Carbon namespace.
    /// Nonisolated so the C callback can compare against it.
    nonisolated private static let signature: FourCharCode = {
        var result: FourCharCode = 0
        for character in "NBhk".utf16 {
            result = (result << 8) + FourCharCode(character)
        }
        return result
    }()

    /// Handlers by Carbon hot-key id. Static because the Carbon callback is a bare C
    /// function pointer with no captured context — it can only look us up by id.
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var eventHandler: EventHandlerRef?
    private static var nextID: UInt32 = 1

    private var registrations: [(id: UInt32, ref: EventHotKeyRef)] = []
    private var combos: [(combo: Combo, handler: () -> Void)] = []
    private var isEnabled = false

    /// How many chords are currently claimed. Zero while released. Exposed so a test can
    /// assert that `RegisterEventHotKey` actually accepted the combos on this OS version
    /// rather than silently failing (Sequoia, for instance, briefly rejected some chords).
    var registeredComboCount: Int { registrations.count }

    /// Declares the chords to claim. Replaces any previous set. Takes effect immediately if
    /// currently enabled, so changing the shortcut in Settings re-registers in place.
    func setCombos(_ combos: [(combo: Combo, handler: () -> Void)]) {
        self.combos = combos
        guard isEnabled else { return }
        unregisterAll()
        registerAll()
    }

    /// Claims (or releases) the chords. Releasing matters: an unregistered chord goes back
    /// to whatever app is frontmost, which is the whole reason Notchboard can claim a plain
    /// chord without permanently stealing it from Xcode.
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            registerAll()
            Self.logger.log("registered \(self.registrations.count, privacy: .public) global hot key(s)")
        } else {
            let count = registrations.count
            unregisterAll()
            Self.logger.log("released \(count, privacy: .public) global hot key(s) back to the system")
        }
    }

    private func registerAll() {
        Self.installEventHandlerIfNeeded()
        for entry in combos {
            let id = Self.nextID
            Self.nextID += 1

            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
            let status = RegisterEventHotKey(
                entry.combo.keyCode,
                entry.combo.carbonModifiers,
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &ref
            )
            guard status == noErr, let ref else {
                // Note this is NOT the "another app took it" case: with `inOptions: 0`,
                // CarbonEvents.h documents that several applications may register the same
                // hot key and all get notified. Failure here means a duplicate registration
                // within this process, or a clash with a kEventHotKeyExclusive holder.
                Self.logger.error("could not register hot key (status \(status, privacy: .public))")
                continue
            }
            Self.handlers[id] = entry.handler
            registrations.append((id: id, ref: ref))
        }
    }

    private func unregisterAll() {
        for registration in registrations {
            UnregisterEventHotKey(registration.ref)
            Self.handlers.removeValue(forKey: registration.id)
        }
        registrations.removeAll()
    }

    private static func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ -> OSStatus in
                GlobalHotKeys.handleCarbonEvent(event)
            },
            1,
            &spec,
            nil,
            &eventHandler
        )
    }

    private nonisolated static func handleCarbonEvent(_ event: EventRef?) -> OSStatus {
        guard let event else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            UInt32(kEventParamDirectObject),
            UInt32(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == signature else {
            return OSStatus(eventNotHandledErr)
        }

        // Carbon dispatches this on the main thread, but hop explicitly rather than assume
        // isolation: a wrong assumption would trap, and a hotkey cannot feel the difference.
        let id = hotKeyID.id
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                handlers[id]?()
            }
        }
        // Claim the event so it stops here instead of reaching the frontmost app.
        return noErr
    }

    // No `deinit` teardown: deinit is nonisolated and these registrations are main-actor
    // state, so cleaning up there would be an unchecked cross-isolation call (the same trap
    // SimulatorWindowTracker had). AppDelegate owns this object for the app's lifetime and
    // calls `setEnabled(false)` in applicationWillTerminate. Carbon registrations are
    // process-scoped anyway, so they die with the process regardless.
}

extension NBHotKeyModifier {
    /// Carbon modifier flags for `RegisterEventHotKey`.
    var carbonFlags: UInt32 {
        switch self {
        case .control: return UInt32(controlKey)
        case .command: return UInt32(cmdKey)
        case .optionCommand: return UInt32(optionKey | cmdKey)
        }
    }

    /// The AppKit equivalent, for the local (in-panel) monitor to match against.
    var appKitFlags: NSEvent.ModifierFlags {
        switch self {
        case .control: return .control
        case .command: return .command
        case .optionCommand: return [.option, .command]
        }
    }
}

extension GlobalHotKeys.Combo {
    /// ⌃K / ⌘K / ⌥⌘K, depending on the configured modifier.
    static func search(modifier: NBHotKeyModifier) -> Self {
        Self(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: modifier.carbonFlags)
    }

    /// ⌃N / ⌘N / ⌥⌘N.
    static func newElement(modifier: NBHotKeyModifier) -> Self {
        Self(keyCode: UInt32(kVK_ANSI_N), carbonModifiers: modifier.carbonFlags)
    }
}
