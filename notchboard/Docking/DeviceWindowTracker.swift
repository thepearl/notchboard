//
//  DeviceWindowTracker.swift
//  notchboard
//
//  Locates a running device host (iOS Simulator or Android emulator — see DeviceKind) and
//  tracks its frontmost window's frame via the Accessibility API, so Notchboard can dock
//  to its real, live position/size — not a mockup. One engine, two kinds: the polling
//  tiers, activation caching and coordinate conversion are platform-neutral, and
//  everything platform-specific routes through `DeviceKind`.
//
//  Polling (rather than AXObserver notifications) is used for simplicity and because AX
//  move notifications don't fire continuously during a live drag anyway. The rate is
//  adaptive: a window can only be dragged while its app is frontmost and a mouse button
//  is down, so the tracker reads at ~60Hz exactly then ("glued to the window" feedback
//  from the first team test), 10Hz while the host is merely frontmost, and the original
//  ~3Hz the rest of the time. `onUpdate` lets the owner reposition the moment a change
//  lands instead of waiting for a timer of its own.
//

import AppKit
import ApplicationServices
import Observation

@Observable
final class DeviceWindowTracker {
    /// Which device host this instance tracks. Fixed at init — AppDelegate owns one
    /// tracker per kind and arbitrates between them.
    let kind: DeviceKind

    init(kind: DeviceKind) {
        self.kind = kind
    }

    /// Whether the host app is currently running at all.
    private(set) var isRunning = false

    /// The host's frontmost window frame, in AppKit (bottom-left origin) screen
    /// coordinates — ready to hand to `NSWindow.setFrame`. `nil` if the host isn't
    /// running, has no window, or Accessibility permission hasn't been granted yet.
    private(set) var windowFrame: CGRect?

    /// The tracked window's AX title — read only for kinds that select their window by
    /// title (the emulator), always nil for the Simulator. Carries the console port that
    /// joins the emulator window to its adb serial. Nil whenever `windowFrame` is.
    private(set) var windowTitle: String?

    /// When the host app last became frontmost (nil = never this launch). Feeds
    /// AppDelegate's docking arbitration: with both a Simulator and an emulator on
    /// screen, the one the user last clicked into wins the panel.
    private(set) var lastActivatedAt: Date?

    /// Fired whenever `isRunning`, the window frame, or `lastActivatedAt` actually
    /// changes, so the owner can reposition immediately — SwiftUI must NOT observe this
    /// class (CLAUDE.md), and a callback beats making AppDelegate poll on a second timer.
    @ObservationIgnored var onUpdate: (() -> Void)?

    private var timer: Timer?
    private var lastReadAt = Date.distantPast

    /// Cached because `desiredInterval` is consulted on every one of the 60 ticks a second
    /// and `NSWorkspace.frontmostApplication` is a cross-process lookup, not a field read.
    /// Activation notifications are exact and arrive far less often than the timer does.
    private var hostIsFrontmost = false
    private var activationObservers: [NSObjectProtocol] = []

    /// True while an AX read is in flight on a background task — skips further ticks so
    /// reads never pile up behind a slow/hung host process.
    private var isReadingFrame = false

    func start() {
        stop()
        observeActivation()
        // A 60Hz heartbeat whose ticks are a date comparison against a cached Bool, and
        // one `NSEvent.pressedMouseButtons` read while the host is frontmost:
        // `desiredInterval` decides how fresh the frame needs to be right now, and only
        // an overdue tick pays for an AX read.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer?.tolerance = 0 // coalescing would defeat the drag-follow tier
        poll()
    }

    private func tick() {
        guard Date().timeIntervalSince(lastReadAt) >= desiredInterval else { return }
        poll()
    }

    /// How stale the frame is allowed to be, by what the user could be doing to the
    /// host window right now.
    private var desiredInterval: TimeInterval {
        guard hostIsFrontmost else {
            return 0.35 // background app: presence tracking is all that's needed
        }
        // Frontmost + button down is the only state a live drag can happen in — follow
        // every tick. Frontmost alone still gets a snappy rate for keyboard/zoom moves.
        return NSEvent.pressedMouseButtons != 0 ? 0 : 0.1
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for observer in activationObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        activationObservers = []
    }

    /// Keeps `hostIsFrontmost` current from activation events rather than asking the
    /// workspace 60 times a second, and stamps `lastActivatedAt` on the way in.
    private func observeActivation() {
        adoptFrontmost(matches(NSWorkspace.shared.frontmostApplication))
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didDeactivateApplicationNotification] {
            activationObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.adoptFrontmost(self.matches(NSWorkspace.shared.frontmostApplication))
                }
            })
        }
    }

    private func matches(_ app: NSRunningApplication?) -> Bool {
        guard let app else { return false }
        return kind.matches(app)
    }

    /// The activation stamp only moves on a genuine background→frontmost transition, so
    /// it stays sticky for arbitration and never rewrites at notification rate.
    private func adoptFrontmost(_ frontmost: Bool) {
        if frontmost, !hostIsFrontmost {
            lastActivatedAt = Date()
            onUpdate?()
        }
        hostIsFrontmost = frontmost
    }

    // No `deinit { stop() }`: deinit is nonisolated, and calling the main-actor-isolated
    // stop() from it is an unchecked cross-isolation call that Swift 6 rejects — and
    // Timer.invalidate must run on the scheduling thread anyway. The tracker is owned by
    // AppDelegate for the app's lifetime; the owner calls stop() in applicationWillTerminate.

    /// Observation notifies on every property *write*, not every value change — a poller
    /// that reassigns identical values a few times per second would re-render any observing
    /// SwiftUI view at that rate. All poll-driven writes go through these equality guards.
    private func setRunning(_ running: Bool) {
        if isRunning != running {
            isRunning = running
            onUpdate?()
        }
    }

    private func setFrame(_ frame: CGRect?) {
        if windowFrame != frame {
            windowFrame = frame
            onUpdate?()
        }
    }

    private func setTitle(_ title: String?) {
        if windowTitle != title {
            windowTitle = title
            onUpdate?()
        }
    }

    private func poll() {
        lastReadAt = Date()
        guard AccessibilityPermission.isTrusted else {
            setRunning(false)
            setFrame(nil)
            setTitle(nil)
            return
        }

        guard let hostApp = NSWorkspace.shared.runningApplications.first(where: {
            kind.matches($0)
        }) else {
            setRunning(false)
            setFrame(nil)
            setTitle(nil)
            return
        }

        setRunning(true)

        // Hidden (⌘H) or minimized — both are "put the device down for later", and both
        // mean there's no visible window to dock against.
        if hostApp.isHidden {
            setFrame(nil)
            setTitle(nil)
            return
        }

        // AX calls can block for seconds when the target process is busy or paused under a
        // debugger — never make them from the main thread. NSScreen, conversely, must be
        // read on the main thread, so the flip height is captured here and passed along.
        guard !isReadingFrame else { return }
        guard let screenHeight = Self.primaryScreenHeight else {
            // Through setFrame like every other write: a direct assignment here skipped the
            // equality guard (re-rendering observers at poll rate) and the onUpdate callback.
            setFrame(nil)
            setTitle(nil)
            return
        }
        isReadingFrame = true
        let pid = hostApp.processIdentifier
        let hostKind = kind
        Task.detached(priority: .userInitiated) { [weak self] in
            let read = Self.frontmostWindowFrame(forProcess: pid, kind: hostKind, primaryScreenHeight: screenHeight)
            // `weak self` is unwrapped here rather than inside the MainActor closure: the
            // closure would otherwise capture the mutable optional binding itself, which
            // Swift 6 rejects.
            await self?.applyPolledFrame(read, pid: pid)
        }
    }

    /// Adopts the result of a background AX read. A read that raced the host quitting,
    /// being hidden/minimized, or having permission revoked must not resurrect a stale
    /// frame, so this re-checks the same conditions `poll()` gates on against current state.
    private func applyPolledFrame(_ read: (frame: CGRect, title: String?)?, pid: pid_t) {
        isReadingFrame = false
        guard isRunning,
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.processIdentifier == pid
              }),
              !app.isHidden else { return }
        setFrame(read?.frame)
        setTitle(read?.title)
    }

    /// AX global coordinates are relative to the *primary* screen's top-left corner — the
    /// screen whose AppKit frame origin is (0, 0). That is usually, but not contractually,
    /// `screens.first`, and using another screen's height mis-docks the panel whenever
    /// the host lives on a display of a different height.
    private static var primaryScreenHeight: CGFloat? {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first
        return primary?.frame.height
    }

    /// Which of the host's windows to dock to. Pure so the emulator's multi-window hazard
    /// (device window + Qt toolbar + extended controls, focus anywhere among them) is
    /// unit-testable without a process. `titles` and `focusedIndex` describe the host's AX
    /// windows in order; the return value indexes into the same order.
    nonisolated static func chooseWindowIndex(
        titles: [String?], focusedIndex: Int?, selection: WindowSelection, kind: DeviceKind
    ) -> Int? {
        guard !titles.isEmpty else { return nil }
        switch selection {
        case .focusedOrFirst:
            // Prefer the app's focused window if it reports one; otherwise the first.
            return focusedIndex ?? 0
        case .titled:
            // Focus proves nothing here — a parse failure on every title means no device
            // window, never a guess at the toolbar.
            return titles.firstIndex { kind.matchesDeviceWindowTitle($0) }
        }
    }

    /// Reads the device window's position + size (and, for `.titled` kinds, its title) for
    /// the given process via AX, converting from AX's top-left-origin coordinate space to
    /// AppKit's bottom-left-origin one. Runs off the main thread; everything it needs is
    /// passed in.
    nonisolated private static func frontmostWindowFrame(
        forProcess pid: pid_t, kind: DeviceKind, primaryScreenHeight: CGFloat
    ) -> (frame: CGRect, title: String?)? {
        let axApp = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        guard windowsResult == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            return nil
        }

        let selection = kind.windowSelection

        // Titles are read only when the selection needs them, so the iOS path pays nothing.
        // (Pattern matching, not ==: the synthesized Equatable is main-actor-isolated
        // under the project's default isolation, and this runs off the main actor.)
        let wantsTitles = if case .titled = selection { true } else { false }
        let titles: [String?] = wantsTitles
            ? windows.map { axString($0, kAXTitleAttribute) }
            : Array(repeating: nil, count: windows.count)

        var focusedIndex: Int?
        if case .focusedOrFirst = selection {
            var focusedRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedRef)
            if let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() {
                let focused = focusedRef as! AXUIElement
                focusedIndex = windows.firstIndex { CFEqual($0, focused) }
            }
        }

        guard let index = chooseWindowIndex(
            titles: titles, focusedIndex: focusedIndex, selection: selection, kind: kind
        ) else {
            return nil
        }
        let window = windows[index]

        // A minimized (or otherwise hidden) window has no meaningful on-screen frame to dock
        // to — treat "host window put down to use later" the same as "no window at all".
        if axBool(window, kAXMinimizedAttribute) == true {
            return nil
        }

        guard let origin = axPoint(window, kAXPositionAttribute),
              let size = axSize(window, kAXSizeAttribute) else {
            return nil
        }

        // AX coordinates: origin is top-left of the primary screen, y grows downward.
        // AppKit coordinates: origin is bottom-left, y grows upward.
        let appKitY = primaryScreenHeight - origin.y - size.height
        return (CGRect(x: origin.x, y: appKitY, width: size.width, height: size.height), titles[index])
    }

    nonisolated private static func axPoint(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let value = ref, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    nonisolated private static func axSize(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let value = ref, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    nonisolated private static func axBool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? Bool
    }

    nonisolated private static func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
}
