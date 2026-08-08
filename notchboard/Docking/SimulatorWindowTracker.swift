//
//  SimulatorWindowTracker.swift
//  notchboard
//
//  Locates the running iOS Simulator app and tracks its frontmost window's frame via the
//  Accessibility API, so Notchboard can dock to its real, live position/size — not a mockup.
//
//  Polling (rather than AXObserver notifications) is used for simplicity and because AX
//  move notifications don't fire continuously during a live drag anyway. The rate is
//  adaptive: a window can only be dragged while its app is frontmost and a mouse button
//  is down, so the tracker reads at ~60Hz exactly then ("glued to the window" feedback
//  from the first team test), 10Hz while Simulator is merely frontmost, and the original
//  ~3Hz the rest of the time. `onUpdate` lets the owner reposition the moment a change
//  lands instead of waiting for a timer of its own.
//

import AppKit
import ApplicationServices
import Observation

@Observable
final class SimulatorWindowTracker {
    /// Bundle identifier of the real iOS Simulator app.
    static let simulatorBundleID = "com.apple.iphonesimulator"

    /// Whether Simulator.app is currently running at all.
    private(set) var isSimulatorRunning = false

    /// The Simulator's frontmost window frame, in AppKit (bottom-left origin) screen
    /// coordinates — ready to hand to `NSWindow.setFrame`. `nil` if Simulator isn't running,
    /// has no window, or Accessibility permission hasn't been granted yet.
    private(set) var simulatorWindowFrame: CGRect?

    /// Fired whenever `isSimulatorRunning` or the window frame actually changes, so the
    /// owner can reposition immediately — SwiftUI must NOT observe this class (CLAUDE.md),
    /// and a callback beats making AppDelegate poll on a second timer.
    @ObservationIgnored var onUpdate: (() -> Void)?

    private var timer: Timer?
    private var lastReadAt = Date.distantPast

    /// True while an AX read is in flight on a background task — skips further ticks so
    /// reads never pile up behind a slow/hung Simulator process.
    private var isReadingFrame = false

    func start() {
        stop()
        // A 60Hz heartbeat whose ticks are almost always a two-comparison no-op:
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
    /// Simulator window right now.
    private var desiredInterval: TimeInterval {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.simulatorBundleID else {
            return 0.35 // background app: presence tracking is all that's needed
        }
        // Frontmost + button down is the only state a live drag can happen in — follow
        // every tick. Frontmost alone still gets a snappy rate for keyboard/zoom moves.
        return NSEvent.pressedMouseButtons != 0 ? 0 : 0.1
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // No `deinit { stop() }`: deinit is nonisolated, and calling the main-actor-isolated
    // stop() from it is an unchecked cross-isolation call that Swift 6 rejects — and
    // Timer.invalidate must run on the scheduling thread anyway. The tracker is owned by
    // AppDelegate for the app's lifetime; the owner calls stop() in applicationWillTerminate.

    /// Observation notifies on every property *write*, not every value change — a poller
    /// that reassigns identical values a few times per second would re-render any observing
    /// SwiftUI view at that rate. All poll-driven writes go through these equality guards.
    private func setRunning(_ running: Bool) {
        if isSimulatorRunning != running {
            isSimulatorRunning = running
            onUpdate?()
        }
    }

    private func setFrame(_ frame: CGRect?) {
        if simulatorWindowFrame != frame {
            simulatorWindowFrame = frame
            onUpdate?()
        }
    }

    private func poll() {
        lastReadAt = Date()
        guard AccessibilityPermission.isTrusted else {
            setRunning(false)
            setFrame(nil)
            return
        }

        guard let simulatorApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == Self.simulatorBundleID
        }) else {
            setRunning(false)
            setFrame(nil)
            return
        }

        setRunning(true)

        // Hidden (⌘H) or minimized — both are "put the Simulator down for later", and both
        // mean there's no visible window to dock against.
        if simulatorApp.isHidden {
            setFrame(nil)
            return
        }

        // AX calls can block for seconds when the target process is busy or paused under a
        // debugger — never make them from the main thread. NSScreen, conversely, must be
        // read on the main thread, so the flip height is captured here and passed along.
        guard !isReadingFrame else { return }
        guard let screenHeight = Self.primaryScreenHeight else {
            simulatorWindowFrame = nil
            return
        }
        isReadingFrame = true
        let pid = simulatorApp.processIdentifier
        Task.detached(priority: .userInitiated) { [weak self] in
            let frame = Self.frontmostWindowFrame(forProcess: pid, primaryScreenHeight: screenHeight)
            // `weak self` is unwrapped here rather than inside the MainActor closure: the
            // closure would otherwise capture the mutable optional binding itself, which
            // Swift 6 rejects.
            await self?.applyPolledFrame(frame, pid: pid)
        }
    }

    /// Adopts the result of a background AX read. A read that raced Simulator quitting,
    /// being hidden/minimized, or having permission revoked must not resurrect a stale
    /// frame, so this re-checks the same conditions `poll()` gates on against current state.
    private func applyPolledFrame(_ frame: CGRect?, pid: pid_t) {
        isReadingFrame = false
        guard isSimulatorRunning,
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.processIdentifier == pid
              }),
              !app.isHidden else { return }
        setFrame(frame)
    }

    /// AX global coordinates are relative to the *primary* screen's top-left corner — the
    /// screen whose AppKit frame origin is (0, 0). That is usually, but not contractually,
    /// `screens.first`, and using another screen's height mis-docks the panel whenever
    /// Simulator lives on a display of a different height.
    private static var primaryScreenHeight: CGFloat? {
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first
        return primary?.frame.height
    }

    /// Reads the frontmost (or first) window's position + size for the given process via AX,
    /// converting from AX's top-left-origin coordinate space to AppKit's bottom-left-origin one.
    /// Runs off the main thread; everything it needs is passed in.
    nonisolated private static func frontmostWindowFrame(forProcess pid: pid_t, primaryScreenHeight: CGFloat) -> CGRect? {
        let axApp = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        guard windowsResult == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
            return nil
        }

        // Prefer the app's focused window if it reports one; otherwise fall back to the first.
        var focusedRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedRef)
        let window: AXUIElement
        if let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() {
            window = (focusedRef as! AXUIElement)
        } else {
            window = windows[0]
        }

        // A minimized (or otherwise hidden) window has no meaningful on-screen frame to dock
        // to — treat "Simulator window put down to use later" the same as "no window at all".
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
        return CGRect(x: origin.x, y: appKitY, width: size.width, height: size.height)
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
}
