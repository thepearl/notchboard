//
//  AppDelegate.swift
//  notchboard
//
//  Hosts Notchboard as a borderless, non-activating floating panel (not a normal window),
//  and continuously repositions/resizes it to hug the real Simulator.app window — the core
//  "docking" mechanic (see vision.md §4, §9). The panel hides itself when Simulator quits,
//  closes, minimizes, or is hidden, and reappears — redocked — the moment Simulator has a
//  visible window again, so it truly behaves as an attachment to Simulator rather than an
//  independent window.
//
//  Also owns the menu-bar status item (the fallback entry point when Simulator isn't running
//  or Accessibility hasn't been granted — see vision.md §9), the Settings window, and global
//  ⌘K / ⌘N shortcuts so the catalogue is reachable even while Xcode/Simulator has focus.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import os

/// Which "shape" the floating panel is currently showing. Only *transitions* between these
/// (not every position update while following Simulator) get an animated resize — continuous
/// tracking during a Simulator window drag should feel 1:1/instant, not laggy.
private enum PanelContentMode: Equatable {
    case onboarding
    case notch
    case notchWithCoachMark
    case expandedPanel
    /// Undocked panel shown from the menu bar when Simulator/Accessibility is unavailable.
    case fallbackPanel
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?

    private let tracker = SimulatorWindowTracker()
    private var viewModel: NotchboardViewModel!
    private var onboarding: OnboardingViewModel!
    /// The room coordinator (vision.md §14.2). Created here — never in a view model's
    /// init — so no test ever opens a socket, the same rule the tracker follows.
    private var syncEngine: SyncEngine?

    private var repositionTimer: Timer?
    private var lastContentMode: PanelContentMode?
    /// The frame most recently handed to `apply` — compared instead of `panel.frame`, which
    /// reports intermediate values while a resize animation is in flight. Comparing the live
    /// frame made the next 0.15s tick "correct" every mode-transition animation with an
    /// instant snap ~150ms in, so the animation never completed.
    private var lastTargetFrame: NSRect?
    /// Bumped whenever visibility intent changes; an in-flight hide whose generation is
    /// stale was superseded by a show and must not order the panel out.
    private var visibilityGeneration = 0
    /// Consuming global shortcuts (Carbon). Registered only while the panel can respond, so
    /// the chord goes back to the rest of the system the moment it can't.
    private let hotKeys = GlobalHotKeys()
    private var hotKeysRegistered = false
    private var hotKeyModifier: NBHotKeyModifier?
    private var localKeyMonitor: Any?

    /// Menu-bar fallback (vision.md §9): when true and no Simulator window is available to
    /// dock to, the panel shows undocked (centred once, then user-draggable) instead of
    /// hiding. Docking always takes precedence the moment Simulator is visible again.
    private var fallbackPanelVisible = false
    private var fallbackMenuItem: NSMenuItem?

    private static let shortcutLog = Logger(subsystem: "flourix.notchboard", category: "shortcuts")

    private static let onboardingSize = CGSize(width: 468, height: 470)
    private static let coachMarkExtraWidth: CGFloat = 16 + NBMetrics.coachMarkWidth + 20
    private static let resizeAnimationDuration: TimeInterval = 0.22

    /// True when the process is hosting a unit-test run (TEST_HOST injection). The tests
    /// construct their own view models, so the app skips all runtime setup — panel, timers,
    /// monitors — and, critically, never loads or saves the user's real state.json.
    private static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }

        // Agent-style app: no Dock icon, no default app menu. The status item below is the
        // fallback entry point instead (see vision.md §9).
        NSApp.setActivationPolicy(.accessory)

        let (viewModel, onboarding) = Self.makeViewModels()
        self.viewModel = viewModel
        self.onboarding = onboarding

        // Sweep Keychain entries no element references any more — deleting state.json (the
        // documented reset path) used to orphan every secret of the old workspace forever.
        // Skipped while a corrupt-state backup exists: the user may restore it, and its
        // elements' secrets must survive until then.
        //
        // The keeping-set MUST span every collection, not just the active one — passing the
        // active workspace's keys here would delete all other collections' secrets on
        // launch. This was the plan's named landmine; PersistenceLandmineTests guards it.
        if !AppStateStore.corruptBackupExists {
            SecretsStore.pruneOrphans(keeping: Set(viewModel.collections.allSecretKeychainKeys))
        }

        setUpSyncEngine(for: viewModel)
        setUpPanel()
        setUpStatusItem()
        installGlobalShortcuts()
        // No notification prompt here. It is asked for the first time the user clicks
        // "notify me when it's free" — a permission dialog before any expressed interest
        // gets denied by reflex, and that denial is only reversible in System Settings.

        // The panel repositions the moment the tracker lands a change — during a drag the
        // tracker reads at ~60Hz, and waiting for a timer of our own is where the old
        // rubber-band lag came from.
        tracker.onUpdate = { [weak self] in
            self?.updatePanelFrame()
        }
        tracker.start()

        // The window level and the chords react to app switches the instant they happen —
        // the panel dropping behind Chrome must not wait out a timer tick.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncPanelLevel()
                self?.syncHotKeyRegistration()
            }
        }

        // Slow fallback tick for everything not event-driven: the deferred coach mark,
        // SwiftUI-side state changes (expand/collapse) that need a frame pass, and hotkey
        // re-checks. Frame-following no longer rides this — see tracker.onUpdate above.
        repositionTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.updatePanelFrame()
        }

        // Place and show the panel now rather than waiting ~0.15s for the first tick —
        // the delay showed the panel at its placeholder frame in the screen corner on
        // every launch. makeKey afterwards so onboarding's name field can take focus.
        updatePanelFrame()
        panel.makeKey()

        // Files that launched the app (double-clicked .notchboard) queued while the view
        // models didn't exist yet — import them now.
        if !pendingOpenURLs.isEmpty {
            let urls = pendingOpenURLs
            pendingOpenURLs = []
            importCollections(from: urls)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        // Hand the chords back explicitly rather than relying on process teardown.
        hotKeys.setEnabled(false)
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        repositionTimer?.invalidate()
        tracker.stop()
        // Say goodbye to every room properly (retained offline presence) so teammates see
        // the claims render free now rather than after the broker's will timeout.
        syncEngine?.sleepAll()

        // Saves are normally debounced (see NotchboardSceneView.persist); flush a final
        // immediate write so the last half-second of changes isn't lost on quit.
        AppStateStore.save(viewModel.persistableState(
            onboardingCompleted: !onboarding.isPresented,
            onboardingName: onboarding.name
        ))
    }

    // MARK: - Setup

    /// Wires the sync seam end to end: local store mutations → engine → room, and room
    /// events → view model copy. Rooms whose password is in the Keychain reconnect here
    /// at launch (the password prompt is a join-time affordance, not a launch-time one).
    private func setUpSyncEngine(for viewModel: NotchboardViewModel) {
        let memberID = viewModel.selfMemberID
        let engine = SyncEngine(
            store: viewModel.store,
            selfMemberID: memberID,
            selfName: viewModel.selfName,
            transportFactory: { config, brokerPassword in
                // The broker password arrives unsealed from the engine (it lives sealed
                // inside the config, under the room key) — never from the Keychain.
                MQTTSyncTransport(config: config, memberID: memberID, brokerPassword: brokerPassword)
            }
        )
        // Weak on purpose: store → sink → engine → sessions → store would otherwise cycle.
        viewModel.store.changeSink = { [weak engine] change in
            engine?.handleLocalChange(change)
        }
        engine.onEvent = { [weak viewModel] collectionID, event in
            viewModel?.handleRoomEvent(collectionID: collectionID, event: event)
        }
        viewModel.syncEngine = engine
        syncEngine = engine

        // Rejoin every room this Mac already knows the password for.
        for collection in viewModel.collections {
            guard let room = collection.room,
                  let password = RoomKeyStore.roomPassword(for: room) else { continue }
            engine.joinRoom(room, password: password, collectionID: collection.id)
        }

        // The lid: presence must flip promptly and reconnect must re-replay, and neither
        // can rely on the TCP session noticing. Workspace notifications are the signal.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncEngine?.sleepAll() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncEngine?.wakeAll() }
        }
    }

    private static func makeViewModels() -> (NotchboardViewModel, OnboardingViewModel) {
        let viewModel = NotchboardViewModel()
        let onboarding = OnboardingViewModel()

        if let persisted = AppStateStore.load() {
            viewModel.restore(from: persisted)
            onboarding.isPresented = !persisted.onboardingCompleted
            onboarding.name = persisted.onboardingName
        }

        return (viewModel, onboarding)
    }

    private func setUpPanel() {
        let rootView = NotchboardSceneView(viewModel: viewModel, onboarding: onboarding, tracker: tracker)
        let hosting = NSHostingController(rootView: rootView)

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: NBMetrics.panelWidth, height: NBMetrics.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.contentViewController = hosting
        self.panel = panel
        // Not ordered front here: the panel would flash at its placeholder (0,0) frame for
        // one timer tick. applicationDidFinishLaunching positions it first via
        // updatePanelFrame(), whose show() path orders it front at the right place.
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "square.righthalf.filled", accessibilityDescription: "Notchboard")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()

        let header = NSMenuItem(title: "Notchboard", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(makeItem("Toggle Expand / Collapse", #selector(toggleExpandedFromMenu), key: ""))
        let fallbackItem = makeItem("Show Panel (Undocked)", #selector(toggleFallbackFromMenu), key: "")
        menu.addItem(fallbackItem)
        fallbackMenuItem = fallbackItem
        menu.addItem(.separator())
        // Joining sits with import/export because that is what it replaced: the room is
        // reached with a pasted invite now, not a file (vision.md §13.12).
        menu.addItem(makeItem("Join Room with Invite", #selector(joinRoomWithInviteFromMenu), key: ""))
        menu.addItem(makeItem("Export Collection", #selector(exportCollectionFromMenu), key: ""))
        menu.addItem(makeItem("Import Collections", #selector(importCollectionsFromMenu), key: ""))
        menu.addItem(makeItem("Restore Snapshot", #selector(restoreSnapshotFromMenu), key: ""))
        menu.addItem(.separator())
        menu.addItem(makeItem("Settings", #selector(openSettingsFromMenu), key: ","))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Notchboard", #selector(quitFromMenu), key: "q"))

        item.menu = menu
        statusItem = item
    }

    private func makeItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleExpandedFromMenu() {
        viewModel.toggleExpanded()
    }

    @objc private func joinRoomWithInviteFromMenu() {
        revealPanelForFeedback()
        viewModel.joinWithInviteFromMenu()
    }

    /// Menu-bar flows report themselves in toasts, and toasts only render in an expanded
    /// panel (collapsed it is 36pt wide, so one clips to its own status dot). Every menu
    /// action whose outcome the user has to see opens the panel first — including its
    /// failures, which are the ones that must not disappear.
    private func revealPanelForFeedback() {
        viewModel.isExpanded = true
        updatePanelFrame()
    }

    @objc private func toggleFallbackFromMenu() {
        setFallbackVisible(!fallbackPanelVisible)
    }

    private func setFallbackVisible(_ visible: Bool) {
        fallbackPanelVisible = visible
        fallbackMenuItem?.title = visible ? "Dock to Simulator Again" : "Show Panel (Undocked)"
        if visible {
            viewModel.isExpanded = true
            viewModel.showCoachMark = false
        }
        updatePanelFrame()
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    @objc private func exportCollectionFromMenu() {
        revealPanelForFeedback()
        guard let url = WorkspaceFileDialogs.chooseExportDestination(defaultName: viewModel.workspace.name) else { return }
        // Password after destination: cancelling the password prompt costs nothing, whereas
        // deriving a key before knowing whether the user even picks a file would waste the
        // (deliberately slow) PBKDF2 work.
        guard let password = WorkspaceExportFlow.promptForPassword(collectionName: viewModel.workspace.name) else { return }
        do {
            // The room address travels with the file (§14.3: the file is the invitation);
            // exportData strips the local-only firstSyncCompleted flag itself.
            let data = try WorkspaceTransfer.exportData(
                viewModel.workspace, password: password, room: viewModel.activeCollection.room
            )
            try data.write(to: url, options: .atomic)
            viewModel.toast("exported “\(viewModel.workspace.name)” — secrets encrypted", color: .green)
        } catch {
            viewModel.toast("export failed — \(error.localizedDescription)", color: .red)
        }
    }

    /// Imports one collection per chosen file, each added *alongside* the existing ones —
    /// import destroys nothing (vision.md §14, plan Phase 2).
    @objc private func importCollectionsFromMenu() {
        revealPanelForFeedback()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.notchboardCollection, .json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.title = "Import Collections"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        importCollections(from: panel.urls)
    }

    /// Shared by the menu path and the double-click open path.
    private func importCollections(from urls: [URL]) {
        for url in urls {
            do {
                guard let imported = try WorkspaceImportFlow.importInteractively(from: url) else { continue }
                viewModel.addCollection(imported.workspace)
                // §14.3's join moment: the file carried its room address, so the new
                // collection (now active — add() switches to it) offers to go live.
                if let room = imported.room {
                    viewModel.offerToJoinImportedRoom(room, collectionID: viewModel.activeCollectionID)
                }
            } catch {
                viewModel.toast(WorkspaceImportFlow.userMessage(for: error), color: .red)
            }
        }
    }

    @objc private func restoreSnapshotFromMenu() {
        revealPanelForFeedback()
        SnapshotRestoreFlow.run(viewModel: viewModel)
    }

    /// Files opened from Finder (double-click, drag onto the icon, "Open With") arrive
    /// here via the CFBundleDocumentTypes declaration in Info.plist. On a launch-by-
    /// document they can arrive *before* applicationDidFinishLaunching has built the view
    /// models, so they queue rather than being dropped.
    private var pendingOpenURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        guard viewModel != nil else {
            pendingOpenURLs.append(contentsOf: urls)
            return
        }
        importCollections(from: urls)
    }

    @objc private func openSettingsFromMenu() {
        if let settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let view = SettingsView(viewModel: viewModel, onReplayOnboarding: { [weak self] in
            self?.onboarding.reset()
            self?.viewModel.replayOnboarding()
        })
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Notchboard Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Keyboard shortcuts

    /// Where a shortcut event came from. Local events are delivered to Notchboard's own
    /// windows (and can be swallowed); global events are observe-only — macOS never lets a
    /// global monitor consume the keystroke, so the frontmost app acts on it too.
    private enum ShortcutScope {
        case local, global
    }

    private func installGlobalShortcuts() {
        // Local monitor: events already being delivered to Notchboard's own windows. This one
        // *can* swallow, and it always accepts the plain ⌘ chords so the panel behaves like a
        // normal app window regardless of which global modifier is configured.
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            (self?.handleShortcut(event, scope: .local) ?? false) ? nil : event
        }
        syncHotKeyCombos()
    }

    /// Points the Carbon registration at the currently configured modifier. Called at launch
    /// and whenever the Settings picker changes it.
    private func syncHotKeyCombos() {
        let modifier = viewModel.hotKeyModifier
        hotKeyModifier = modifier
        hotKeys.setCombos([
            (combo: .search(modifier: modifier), handler: { [weak self] in self?.performSearchShortcut() }),
            (combo: .newElement(modifier: modifier), handler: { [weak self] in self?.performNewElementShortcut() }),
        ])
    }

    /// Apps in whose company Notchboard is allowed to claim its chords: the iOS development
    /// context the tool exists to sit alongside, plus itself.
    ///
    /// This is the mechanism that makes a plain single-modifier chord defensible. A Carbon
    /// registration is consumed system-wide, and ⌃K/⌃N in particular are real bindings
    /// elsewhere (Cocoa's delete-to-end-of-paragraph and move-down, zsh's kill-line and
    /// down-line-or-history). Rather than take them from the whole machine, Notchboard holds
    /// them only while the user is in Xcode or Simulator, which is exactly where they would
    /// reach for the catalogue. Switch to Terminal and ⌃K is kill-line again on the next tick.
    /// Rectangle uses the same idea in reverse, unregistering its hotkeys while a chosen app
    /// is frontmost.
    private static let hotKeyHostBundleIDs: Set<String> = [
        SimulatorWindowTracker.simulatorBundleID,
        "com.apple.dt.Xcode",
        Bundle.main.bundleIdentifier ?? "flourix.notchboard",
    ]

    /// True while the frontmost app is one Notchboard may claim chords around.
    private var hotKeyHostIsFrontmost: Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return Self.hotKeyHostBundleIDs.contains(bundleID)
    }

    /// Keeps the panel stacked like it's glued to the Simulator window, not floating over
    /// the whole machine. At a permanent `.floating` level the panel stayed on top when
    /// the user switched to Chrome — Chrome covered the Simulator (normal level) but not
    /// the panel, leaving it visibly docked to a window that was no longer there. So the
    /// panel floats only while Simulator (or Notchboard itself — the Settings window)
    /// is frontmost and drops to `.normal` otherwise, where the newly activated app
    /// covers it exactly as it covers Simulator. Deliberately NOT the hotkey set: in
    /// Xcode the panel behaves like any sibling window too ("with Simulator only" —
    /// team feedback). Onboarding and the undocked fallback keep floating — they aren't
    /// glued to anything. Runs on app-activation notifications and the fallback tick,
    /// equality-guarded like everything else on that tick.
    private func syncPanelLevel() {
        guard panel != nil else { return }
        let shouldFloat = onboarding.isPresented || fallbackPanelVisible || simulatorOrSelfIsFrontmost
        let level: NSWindow.Level = shouldFloat ? .floating : .normal
        guard panel.level != level else { return }
        panel.level = level
    }

    private var simulatorOrSelfIsFrontmost: Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return bundleID == SimulatorWindowTracker.simulatorBundleID
            || bundleID == Bundle.main.bundleIdentifier
    }

    /// Claims the global chords only while they can be acted on *and* the user is in the
    /// iOS-development context, and hands them straight back otherwise.
    private func syncHotKeyRegistration() {
        if viewModel.hotKeyModifier != hotKeyModifier {
            syncHotKeyCombos()
            // Force a re-register so the new chord takes effect immediately.
            hotKeys.setEnabled(false)
            hotKeysRegistered = false
        }
        let shouldRegister = !onboarding.isPresented && panelIsInteractable && hotKeyHostIsFrontmost
        guard shouldRegister != hotKeysRegistered else { return }
        hotKeysRegistered = shouldRegister
        hotKeys.setEnabled(shouldRegister)
    }

    /// True when the panel is actually on screen for the user to see the shortcut's effect.
    /// Shortcuts must never mutate an invisible panel — a Simulator that is running but
    /// hidden/minimized keeps `isSimulatorRunning` true while the panel is ordered out, and
    /// stale state would surface later as a panel reopening in a view the user never chose.
    private var panelIsInteractable: Bool {
        if fallbackPanelVisible { return true }
        return tracker.isSimulatorRunning && tracker.simulatorWindowFrame != nil && panel.isVisible
    }

    /// Returns `true` if the event was one of our shortcuts and was handled (so the local
    /// monitor can swallow it instead of also delivering it to whatever's focused).
    ///
    /// Only handles events already destined for Notchboard's own panel. Reaching the
    /// catalogue from *another* app is the Carbon registration's job (see GlobalHotKeys) —
    /// an `NSEvent` global monitor cannot consume a keystroke, which is why the previous
    /// version double-triggered Xcode's New File on every ⌘N.
    private func handleShortcut(_ event: NSEvent, scope: ShortcutScope) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Inside the panel, accept the plain ⌘ chords as well as whatever global modifier is
        // configured: within our own window there is nothing to collide with, and ⌘K/⌘N is
        // what the panel's own copy advertises.
        let accepted: [NSEvent.ModifierFlags] = [.command, viewModel.hotKeyModifier.appKitFlags]
        guard accepted.contains(modifiers) else { return false }
        // Only when the panel itself is focused — a ⌘N typed into the Settings window (or any
        // future window) must reach that window, not be swallowed here.
        guard event.window === panel else { return false }

        // ⌘, before the onboarding/interactable gate: settings must be reachable from the
        // panel at any time, and this is the only thing answering that chord now that the
        // SwiftUI Settings scene's command group is gone (see notchboardApp).
        if modifiers == .command, event.charactersIgnoringModifiers == "," {
            openSettingsFromMenu()
            return true
        }
        guard !onboarding.isPresented, panelIsInteractable else { return false }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "k":
            performSearchShortcut()
            return true
        case "n":
            performNewElementShortcut()
            return true
        default:
            return false
        }
    }

    /// Open the catalogue and focus search. Shared by the in-panel ⌘K and the global chord.
    private func performSearchShortcut() {
        guard !onboarding.isPresented, panelIsInteractable else { return }
        Self.shortcutLog.log("search shortcut fired")
        viewModel.isExpanded = true
        viewModel.currentView = .list
        viewModel.searchFocusToken += 1
        bringPanelForward()
    }

    /// Open the add-element form. Shared by the in-panel ⌘N and the global chord.
    private func performNewElementShortcut() {
        guard !onboarding.isPresented, panelIsInteractable else { return }
        Self.shortcutLog.log("new-element shortcut fired")
        viewModel.isExpanded = true
        viewModel.openAdd()
        bringPanelForward()
    }

    /// A global chord can fire while another app is frontmost, so the panel has to come
    /// forward and take key focus for typing to land in it. The panel is a non-activating
    /// panel, so this doesn't steal activation from Xcode or Simulator — the app itself never
    /// becomes frontmost (see FloatingPanel and CLAUDE.md).
    private func bringPanelForward() {
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    // MARK: - Panel positioning

    private func updatePanelFrame() {
        guard let panel else { return }

        // Claim or release the global chords as availability changes. Cheap: this only calls
        // into Carbon on an actual transition.
        syncHotKeyRegistration()
        syncPanelLevel()

        // Onboarding may have finished before Simulator ever ran — deliver the deferred
        // coach mark the first time it appears instead of silently skipping it. Lives on
        // this AppKit-side tick (not a SwiftUI onChange) so no view has to observe the
        // tracker, whose per-poll property writes would re-render the whole panel tree.
        if tracker.isSimulatorRunning, viewModel.pendingCoachMark, !onboarding.isPresented {
            viewModel.pendingCoachMark = false
            viewModel.showCoachMark = true
            viewModel.isExpanded = false
        }

        // Onboarding always shows regardless of whether Simulator happens to be running yet —
        // setup shouldn't require Simulator to already be open. Positioned once on entry
        // (centred on the screen with the mouse) and then left alone, draggable — a per-tick
        // recentre made the dialog teleport between displays whenever the cursor crossed
        // screens, mid-typing included.
        if onboarding.isPresented {
            show(panel)
            panel.isMovableByWindowBackground = true
            guard lastContentMode != .onboarding else { return }
            let size = Self.onboardingSize
            guard let screen = screenNearMouse() else { return }
            let origin = CGPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2)
            apply(NSRect(origin: origin, size: size), to: panel, mode: .onboarding)
            return
        }

        // "Show Panel (Undocked)" is a request, not a fallback, and it outranks docking.
        // It used to be checked only when no Simulator window could be found, so with
        // Simulator running the menu item silently did nothing — which is exactly how it
        // read to the first team ("doesn't seem to do anything at all"). Docking resumes
        // when the user asks for it back, not the moment Simulator reappears.
        if fallbackPanelVisible {
            layoutFallbackPanel(panel)
            return
        }

        // Docked to Simulator: once onboarded, Notchboard only exists alongside a running,
        // visible Simulator window.
        guard tracker.isSimulatorRunning, let simFrame = tracker.simulatorWindowFrame else {
            hide(panel)
            return
        }
        panel.isMovableByWindowBackground = false
        show(panel)

        let mode: PanelContentMode = viewModel.isExpanded
            ? .expandedPanel
            : (viewModel.showCoachMark ? .notchWithCoachMark : .notch)

        let size: CGSize
        switch mode {
        case .expandedPanel, .fallbackPanel:
            size = CGSize(width: NBMetrics.panelWidth, height: NBMetrics.panelHeight)
        case .notchWithCoachMark:
            size = CGSize(width: NBMetrics.notchWidth + Self.coachMarkExtraWidth, height: NBMetrics.notchHeight + 60)
        case .notch, .onboarding:
            size = CGSize(width: NBMetrics.notchWidth, height: NBMetrics.notchHeight)
        }

        // The collapsed notch sits a touch below the window's vertical centre (team
        // feedback) — the expanded panel stays centred.
        let isNotchMode = mode == .notch || mode == .notchWithCoachMark
        let frame = Self.dockedFrame(
            simFrame: simFrame,
            size: size,
            edge: viewModel.dockEdge,
            clampedTo: screenContaining(simFrame)?.visibleFrame,
            verticalOffset: isNotchMode ? -Self.notchVerticalOffset : 0
        )
        apply(frame, to: panel, mode: mode)
    }

    /// How far below the Simulator window's vertical centre the collapsed notch sits.
    static let notchVerticalOffset: CGFloat = 10

    /// The docked panel frame: flush against the chosen Simulator window edge, vertically
    /// centred on it, then clamped to the screen's visible frame. Without the clamp, a
    /// Simulator window flush against the screen edge (zoomed, fullscreen) put the whole
    /// panel offscreen — still "visible" as far as AppKit was concerned, but unreachable.
    /// Borderless panels get none of AppKit's usual titled-window frame constraining.
    static func dockedFrame(simFrame: NSRect, size: CGSize, edge: NBDockEdge, clampedTo visible: NSRect?, verticalOffset: CGFloat = 0) -> NSRect {
        let x = edge == .right ? simFrame.maxX : simFrame.minX - size.width
        // AppKit is bottom-left origin: a negative offset moves the window DOWN screen.
        let y = simFrame.midY - size.height / 2 + verticalOffset
        var frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        if let visible {
            frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        }
        return frame
    }

    /// The screen the Simulator window is (mostly) on — used to clamp the docked panel so
    /// it can't land offscreen.
    private func screenContaining(_ rect: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.screens.first
    }

    /// Lays out the undocked fallback panel. Positioned once on entry (centred on the
    /// screen with the mouse), then left alone so the user can drag it around — a per-tick
    /// reposition would fight the drag. Collapsing while undocked dismisses the panel,
    /// since a notch docked to nothing makes no sense.
    private func layoutFallbackPanel(_ panel: NSPanel) {
        // Collapsing an undocked panel means "go back to the normal rules": redock to
        // Simulator as a notch if there is one, and otherwise dismiss (a notch docked to
        // nothing makes no sense) — re-expanded, so the next dock isn't a stranded notch.
        guard viewModel.isExpanded else {
            let canDock = tracker.isSimulatorRunning && tracker.simulatorWindowFrame != nil
            setFallbackVisible(false)
            if !canDock { viewModel.isExpanded = true }
            return
        }
        show(panel)
        panel.isMovableByWindowBackground = true
        guard lastContentMode != .fallbackPanel else { return }
        let size = CGSize(width: NBMetrics.panelWidth, height: NBMetrics.panelHeight)
        guard let screen = screenNearMouse() else { return }
        let origin = CGPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2)
        apply(NSRect(origin: origin, size: size), to: panel, mode: .fallbackPanel)
    }

    /// The screen containing the mouse cursor, falling back to the primary screen — used so
    /// the onboarding dialog (which has no Simulator to anchor to yet) appears wherever the
    /// user is actually working on multi-monitor setups, rather than always on the primary
    /// display.
    private func screenNearMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.screens.first
    }

    private func show(_ panel: NSPanel) {
        // Supersede any in-flight hide: its completion must not order the panel out from
        // under a state that wants it visible (a brief Cmd-H + unhide flickered the panel).
        visibilityGeneration += 1
        guard !panel.isVisible else {
            // Restore alpha only if a superseded hide left it mid-fade — an unconditional
            // write would invalidate the window on every 0.15s tick.
            if panel.alphaValue != 1 { panel.alphaValue = 1 }
            return
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    private func hide(_ panel: NSPanel) {
        guard panel.isVisible else { return }
        visibilityGeneration += 1
        let generation = visibilityGeneration
        lastContentMode = nil // force a fresh (non-animated) frame snap next time it reappears
        lastTargetFrame = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, generation == self.visibilityGeneration else {
                // A show superseded this hide mid-fade — leave the panel up.
                panel.alphaValue = 1
                return
            }
            panel.orderOut(nil)
            panel.alphaValue = 1
        })
    }

    /// How long a follow glide lasts. The tracker delivers discrete position samples
    /// (~30ms apart during a drag); gliding to each one and retargeting mid-glide
    /// interpolates them into continuous motion — snapping to each sample read as
    /// stepping. Short enough that the panel trails the window by less than a fingertip.
    private static let followAnimationDuration: TimeInterval = 0.12

    /// Applies a new frame to the panel. Position updates while following Simulator
    /// (the user dragging its window) glide with a short ease-out so discrete tracker
    /// samples read as one motion; genuine content mode changes (collapse ↔ expand,
    /// coach mark appearing, etc.) animate at their own pace. The very first placement
    /// after launch or a hide snaps without animating — there is no previous frame worth
    /// animating from.
    private func apply(_ frame: NSRect, to panel: NSPanel, mode: PanelContentMode) {
        let isModeTransition = lastContentMode != nil && lastContentMode != mode
        // Compare against the last *target*, never the live frame: mid-animation the live
        // frame is intermediate, and treating it as drift snapped every transition
        // animation dead ~150ms in.
        guard isModeTransition || frame != lastTargetFrame else { return }
        let isFirstPlacement = lastTargetFrame == nil
        lastContentMode = mode
        lastTargetFrame = frame

        if isModeTransition {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.resizeAnimationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else if isFirstPlacement || !panel.isVisible {
            panel.setFrame(frame, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.followAnimationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        }
    }
}
