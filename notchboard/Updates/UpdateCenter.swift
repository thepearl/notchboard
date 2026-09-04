//
//  UpdateCenter.swift
//  notchboard
//
//  The state behind the Updates section, the menu-bar item and the icon dot (vision.md §13.20).
//  A scheduled check that finds something never interrupts: Sparkle hands the reminder to this
//  object, which lights a static dot on the menu-bar icon, retitles the menu item and fills the
//  Settings row. The user installs when they choose, from either place, and Sparkle's own dialog
//  takes over from there.
//
//  Written through equality guards like the tracker: the 0.15s tick reads these properties, and
//  Observation notifies on every write, not every change.
//

import Foundation

@Observable
final class UpdateCenter {
    enum Unavailability: Equatable {
        /// Ad-hoc signed, so an update would swap the identity the Accessibility grant is bound to.
        case builtFromSource
    }

    enum State: Equatable {
        case unavailable(Unavailability)
        case idle(lastChecked: Date?)
        case checking
        case available(version: String)
        case failed(message: String)
    }

    let installedVersion: String
    private(set) var state: State
    /// The dot on the menu-bar icon. Lit only by a reminder Sparkle handed to the app.
    private(set) var showsIndicator = false
    private(set) var canCheck = false
    /// A read cache of Sparkle's own setting, written only from the driver's event. Never
    /// persisted here: Sparkle keeps it in its defaults and documents not to shadow it.
    private(set) var automaticallyChecks = false
    /// True while Sparkle has a window up. The panel stops floating for the duration so the
    /// dialog can never hide under it (AppDelegate.syncPanelLevel).
    private(set) var isPresentingUpdateUI = false

    @ObservationIgnored private let driver: UpdateDriver?
    /// The last check that completed, so a scheduled failure can fall back to the previous
    /// "checked … ago" instead of pinning an error for a day.
    @ObservationIgnored private var lastCompletedCheck: Date?

    /// A self-built copy ignores the driver entirely (BuildProvenance explains why).
    init(provenance: BuildProvenance, driver: UpdateDriver?) {
        installedVersion = provenance.installedVersion
        if provenance.isSelfBuilt || driver == nil {
            self.driver = nil
            state = .unavailable(.builtFromSource)
        } else {
            self.driver = driver
            lastCompletedCheck = driver?.lastUpdateCheckDate
            state = .idle(lastChecked: lastCompletedCheck)
        }
    }

    var isSelfBuilt: Bool {
        if case .unavailable = state { return true }
        return false
    }

    func start() {
        guard let driver else { return }
        driver.onEvent = { [weak self] event in self?.handle(event) }
        driver.start()
        // Sparkle only knows when it last checked once its updater is running, so the date read
        // in init is nil in production. Re-read it here or the row says "not checked yet" for
        // the whole session, however recently a check ran.
        if case .idle = state, let date = driver.lastUpdateCheckDate {
            lastCompletedCheck = date
            setState(.idle(lastChecked: date))
        }
    }

    func checkForUpdates() {
        guard let driver, canCheck else { return }
        driver.checkForUpdates()
    }

    /// Forwards only. The mirror changes when Sparkle reports the write, not before.
    func setAutomaticallyChecks(_ enabled: Bool) {
        driver?.setAutomaticallyChecks(enabled)
    }

    var availableVersion: String? {
        if case .available(let version) = state { return version }
        return nil
    }

    /// The menu item and the Settings button share this title.
    var actionTitle: String {
        if let availableVersion { return "Update to \(availableVersion)" }
        return "Check for Updates"
    }

    /// Lowercase with a middle dot, like the room status beside it in Settings.
    func statusText(now: Date = Date()) -> String {
        switch state {
        case .unavailable(.builtFromSource): return "built from source · update by rebuilding"
        case .idle(nil): return "not checked yet"
        case .idle(let date?): return "up to date · checked \(Self.relativeAge(from: date, to: now))"
        case .checking: return "checking…"
        case .available(let version): return "\(version) available"
        case .failed(let message): return message
        }
    }

    // MARK: - Pure rules (tested without Sparkle)

    /// Sparkle's error codes, mapped to what the user can do about them. Translocation and
    /// disk-image errors are persistent and actionable, so they show whatever started the check.
    static func failureMessage(code: Int) -> String {
        switch code {
        case 1003, 1005: return "move Notchboard to Applications to update"
        case 1000, 1002, 1004, 1007, 2000, 2001: return "couldn't reach GitHub · try again later"
        case 3000...3002, 4000...4012: return "the update couldn't be installed · download it from GitHub"
        default: return "update check failed · try again later"
        }
    }

    /// A failure a scheduled check may surface: the app is running from a place Sparkle cannot
    /// update, which stays true until the user moves it.
    static func isPersistentFailure(code: Int) -> Bool {
        code == 1003 || code == 1005
    }

    static func relativeAge(from date: Date, to now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(seconds / 60)) min ago"
        case ..<86400: return "\(Int(seconds / 3600)) h ago"
        case ..<172_800: return "yesterday"
        default: return "\(Int(seconds / 86400)) days ago"
        }
    }

    // MARK: - Reducer

    private func handle(_ event: UpdateEvent) {
        switch event {
        case .canCheckChanged(let value):
            setCanCheck(value)
        case .automaticChecksChanged(let value):
            setAutomaticallyChecksMirror(value)
        case .checkStarted(let userInitiated):
            handleCheckStarted(userInitiated: userInitiated)
        case .foundUpdate(let version, let checkedAt):
            lastCompletedCheck = checkedAt
            setState(.available(version: version))
        case .reminderHandedToApp(let version, let checkedAt):
            lastCompletedCheck = checkedAt
            setState(.available(version: version))
            setIndicator(true)
        case .noUpdate(let checkedAt):
            lastCompletedCheck = checkedAt
            setState(.idle(lastChecked: checkedAt))
            setIndicator(false)
        case .failed(let code, let userInitiated):
            handleFailure(code: code, userInitiated: userInitiated)
        case .userChose(let choice):
            handleChoice(choice)
        case .updateUIVisible(let visible):
            setPresentingUpdateUI(visible)
        case .userAttended:
            setIndicator(false)
        case .sessionFinished:
            setIndicator(false)
            setPresentingUpdateUI(false)
            if case .checking = state {
                setState(.idle(lastChecked: lastCompletedCheck))
            }
        }
    }

    /// A quiet re-check must not disturb an update already on offer: `.foundUpdate` replaces the
    /// version and `.noUpdate` returns to idle, as before. A user-initiated check always shows
    /// Sparkle's own progress, so "checking…" is right there.
    private func handleCheckStarted(userInitiated: Bool) {
        if !userInitiated, case .available = state { return }
        setState(.checking)
    }

    /// Sparkle is silent about scheduled failures too. An offline daily check must not pin
    /// "couldn't reach GitHub" in Settings until tomorrow; a persistent, actionable condition
    /// (running translocated or from a disk image) is shown whatever started the check.
    private func handleFailure(code: Int, userInitiated: Bool) {
        if userInitiated || Self.isPersistentFailure(code: code) {
            setState(.failed(message: Self.failureMessage(code: code)))
        } else if case .checking = state {
            setState(.idle(lastChecked: lastCompletedCheck))
        }
    }

    private func handleChoice(_ choice: UpdateChoice) {
        switch choice {
        case .install:
            break
        case .dismiss:
            // "Remind Me Later": the update is still real, so the title stays "Update to x"
            // and only the dot goes, because the user has now seen it.
            setIndicator(false)
        case .skip:
            setState(.idle(lastChecked: lastCompletedCheck))
            setIndicator(false)
        }
    }

    private func setState(_ new: State) {
        guard state != new else { return }
        state = new
    }

    private func setIndicator(_ new: Bool) {
        guard showsIndicator != new else { return }
        showsIndicator = new
    }

    private func setCanCheck(_ new: Bool) {
        guard canCheck != new else { return }
        canCheck = new
    }

    private func setAutomaticallyChecksMirror(_ new: Bool) {
        guard automaticallyChecks != new else { return }
        automaticallyChecks = new
    }

    private func setPresentingUpdateUI(_ new: Bool) {
        guard isPresentingUpdateUI != new else { return }
        isPresentingUpdateUI = new
    }
}
