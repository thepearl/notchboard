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

    private var repositionTimer: Timer?
    private var lastContentMode: PanelContentMode?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    /// Menu-bar fallback (vision.md §9): when true and no Simulator window is available to
    /// dock to, the panel shows undocked (centred once, then user-draggable) instead of
    /// hiding. Docking always takes precedence the moment Simulator is visible again.
    private var fallbackPanelVisible = false
    private var fallbackMenuItem: NSMenuItem?

    private static let onboardingSize = CGSize(width: 468, height: 470)
    private static let coachMarkExtraWidth: CGFloat = 16 + NBMetrics.coachMarkWidth + 20
    private static let resizeAnimationDuration: TimeInterval = 0.22

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent-style app: no Dock icon, no default app menu. The status item below is the
        // fallback entry point instead (see vision.md §9).
        NSApp.setActivationPolicy(.accessory)

        let (viewModel, onboarding) = Self.makeViewModels()
        self.viewModel = viewModel
        self.onboarding = onboarding

        setUpPanel()
        setUpStatusItem()
        installGlobalShortcuts()
        Notifier.requestAuthorization()

        tracker.start()

        // Reposition/resize/show-hide as onboarding state, panel expansion, coach mark, or
        // the Simulator's real presence/window frame changes. Polling keeps this simple; see
        // SimulatorWindowTracker for the same tradeoff on the tracking side.
        repositionTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.updatePanelFrame()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        repositionTimer?.invalidate()
        tracker.stop()

        // Saves are normally debounced (see NotchboardSceneView.persist); flush a final
        // immediate write so the last half-second of changes isn't lost on quit.
        AppStateStore.save(viewModel.persistableState(
            onboardingCompleted: !onboarding.isPresented,
            onboardingName: onboarding.name
        ))
    }

    // MARK: - Setup

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
        panel.orderFrontRegardless()
        panel.makeKey()
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
        menu.addItem(makeItem("Replay Onboarding…", #selector(replayOnboardingFromMenu), key: ""))
        menu.addItem(.separator())
        menu.addItem(makeItem("Export Workspace…", #selector(exportWorkspaceFromMenu), key: ""))
        menu.addItem(makeItem("Import Workspace…", #selector(importWorkspaceFromMenu), key: ""))
        menu.addItem(.separator())
        menu.addItem(makeItem("Settings…", #selector(openSettingsFromMenu), key: ","))
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

    @objc private func replayOnboardingFromMenu() {
        onboarding.reset()
    }

    @objc private func toggleFallbackFromMenu() {
        setFallbackVisible(!fallbackPanelVisible)
    }

    private func setFallbackVisible(_ visible: Bool) {
        fallbackPanelVisible = visible
        fallbackMenuItem?.title = visible ? "Hide Undocked Panel" : "Show Panel (Undocked)"
        if visible {
            viewModel.isExpanded = true
            viewModel.showCoachMark = false
        }
        updatePanelFrame()
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    @objc private func exportWorkspaceFromMenu() {
        let data: Data
        do {
            data = try WorkspaceTransfer.exportData(viewModel.workspace)
        } catch {
            viewModel.toast("export failed — \(error.localizedDescription)", color: .red)
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(viewModel.workspace.name).notchboard.json"
        panel.title = "Export Workspace"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            viewModel.toast("workspace exported (secrets not included)", color: .green)
        } catch {
            viewModel.toast("export failed — \(error.localizedDescription)", color: .red)
        }
    }

    @objc private func importWorkspaceFromMenu() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Workspace"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let workspace = try WorkspaceTransfer.importWorkspace(from: data)
            viewModel.replaceWorkspace(with: workspace)
        } catch {
            viewModel.toast("import failed — not a valid workspace file", color: .red)
        }
    }

    @objc private func openSettingsFromMenu() {
        if let settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let view = SettingsView(viewModel: viewModel, onReplayOnboarding: { [weak self] in self?.onboarding.reset() })
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

    // MARK: - Global keyboard shortcuts

    private func installGlobalShortcuts() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            (self?.handleGlobalShortcut(event) ?? false) ? nil : event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handleGlobalShortcut(event)
        }
    }

    /// Returns `true` if the event was one of our shortcuts and was handled (so the local
    /// monitor can swallow it instead of also delivering it to whatever's focused).
    @discardableResult
    private func handleGlobalShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else { return false }
        guard tracker.isSimulatorRunning || fallbackPanelVisible, !onboarding.isPresented else { return false }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "k":
            viewModel.isExpanded = true
            viewModel.currentView = .list
            viewModel.searchFocusToken += 1
            return true
        case "n":
            viewModel.isExpanded = true
            viewModel.openAdd()
            return true
        default:
            return false
        }
    }

    // MARK: - Panel positioning

    private func updatePanelFrame() {
        guard let panel else { return }

        // Onboarding always shows regardless of whether Simulator happens to be running yet —
        // setup shouldn't require Simulator to already be open.
        if onboarding.isPresented {
            show(panel)
            let size = Self.onboardingSize
            guard let screen = screenNearMouse() else { return }
            let origin = CGPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2)
            apply(NSRect(origin: origin, size: size), to: panel, mode: .onboarding)
            return
        }

        // Docked to Simulator: once onboarded, Notchboard normally only exists alongside a
        // running, visible Simulator window — unless the user asked for the undocked
        // fallback from the menu bar. The instant Simulator is visible again, docking
        // takes precedence and the panel snaps back to its edge.
        guard tracker.isSimulatorRunning, let simFrame = tracker.simulatorWindowFrame else {
            if fallbackPanelVisible {
                layoutFallbackPanel(panel)
            } else {
                hide(panel)
            }
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

        // Dock flush against the Simulator window's right edge, vertically centered on it.
        let x = simFrame.maxX
        let y = simFrame.midY - size.height / 2
        apply(NSRect(x: x, y: y, width: size.width, height: size.height), to: panel, mode: mode)
    }

    /// Lays out the undocked fallback panel. Positioned once on entry (centred on the
    /// screen with the mouse), then left alone so the user can drag it around — a per-tick
    /// reposition would fight the drag. Collapsing while undocked dismisses the panel,
    /// since a notch docked to nothing makes no sense.
    private func layoutFallbackPanel(_ panel: NSPanel) {
        guard viewModel.isExpanded else {
            setFallbackVisible(false)
            viewModel.isExpanded = true
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
        guard !panel.isVisible else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    private func hide(_ panel: NSPanel) {
        guard panel.isVisible else { return }
        lastContentMode = nil // force a fresh (non-animated) frame snap next time it reappears
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
        })
    }

    /// Applies a new frame to the panel. Position-only updates while following Simulator
    /// (e.g. the user dragging its window) snap instantly for 1:1 tracking; genuine content
    /// mode changes (collapse ↔ expand, coach mark appearing, etc.) animate smoothly.
    private func apply(_ frame: NSRect, to panel: NSPanel, mode: PanelContentMode) {
        guard panel.frame != frame else { return }

        let isModeTransition = lastContentMode != mode
        lastContentMode = mode

        if isModeTransition {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.resizeAnimationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }
}
