//
//  UpdateCenterTests.swift
//  notchboardTests
//
//  The rules behind the quiet update flow (vision.md §13.20), run against the fake driver: which
//  event lights the menu-bar dot, what a scheduled failure may do to the Settings row, what each
//  answer in Sparkle's dialog leaves behind, and that a self-built copy never touches the driver.
//

import Foundation
import Testing
@testable import notchboard

@Suite("Update centre")
@MainActor
struct UpdateCenterTests {

    private static let release = BuildProvenance(
        installedVersion: "1.2", buildNumber: "10200",
        teamIdentifier: BuildProvenance.releaseTeamIdentifier
    )
    private static let selfBuilt = BuildProvenance(installedVersion: "1.2", buildNumber: "1", teamIdentifier: nil)
    /// When a find happened, later than any seed a test passes to `started(lastCheck:)`.
    private static let found = Date(timeIntervalSince1970: 2_000_000)

    private func started(lastCheck: Date? = nil) -> (UpdateCenter, FakeUpdateDriver) {
        let driver = FakeUpdateDriver(lastUpdateCheckDate: lastCheck)
        let center = UpdateCenter(provenance: Self.release, driver: driver)
        center.start()
        return (center, driver)
    }

    @Test("A self-built copy never starts or asks the driver")
    func selfBuiltIgnoresDriver() {
        let driver = FakeUpdateDriver()
        let center = UpdateCenter(provenance: Self.selfBuilt, driver: driver)
        center.start()
        center.checkForUpdates()
        center.setAutomaticallyChecks(false)
        #expect(center.state == .unavailable(.builtFromSource))
        #expect(center.isSelfBuilt)
        #expect(driver.startCount == 0)
        #expect(driver.checkCount == 0)
        #expect(driver.automaticallyChecks)
        #expect(!center.canCheck)
        #expect(center.statusText() == "built from source · update by rebuilding")
    }

    @Test("A release copy starts idle at the driver's last check and mirrors its flags")
    func releaseStartsIdle() {
        let last = Date(timeIntervalSince1970: 1_000_000)
        let (center, driver) = started(lastCheck: last)
        #expect(driver.startCount == 1)
        #expect(center.state == .idle(lastChecked: last))
        #expect(center.canCheck)
        #expect(center.automaticallyChecks)
        #expect(!center.isSelfBuilt)
        #expect(center.actionTitle == "Check for Updates")
    }

    @Test("The last check date is read again once the driver is running")
    func lastCheckReadAfterStart() {
        // Sparkle answers nil until its updater is started, which is how production behaves.
        let driver = FakeUpdateDriver()
        let center = UpdateCenter(provenance: Self.release, driver: driver)
        #expect(center.statusText() == "not checked yet")
        driver.lastUpdateCheckDate = Date(timeIntervalSince1970: 1_000_000)
        center.start()
        #expect(center.state == .idle(lastChecked: Date(timeIntervalSince1970: 1_000_000)))
    }

    @Test("Only a reminder Sparkle handed to the app lights the dot")
    func reminderLightsDot() {
        let (center, driver) = started()
        driver.emit(.checkStarted(userInitiated: false))
        #expect(center.statusText() == "checking…")
        driver.emit(.foundUpdate(version: "1.3", checkedAt: Self.found))
        #expect(center.state == .available(version: "1.3"))
        #expect(!center.showsIndicator, "a find alone is what Sparkle shows itself for user checks")
        driver.emit(.reminderHandedToApp(version: "1.3", checkedAt: Self.found))
        #expect(center.showsIndicator)
        #expect(center.actionTitle == "Update to 1.3")
        #expect(center.statusText() == "1.3 available")
        #expect(center.availableVersion == "1.3")
    }

    @Test("A later find replaces the version on offer")
    func laterFindReplacesVersion() {
        let (center, driver) = started()
        driver.emit(.reminderHandedToApp(version: "1.3", checkedAt: Self.found))
        driver.emit(.foundUpdate(version: "1.4", checkedAt: Self.found))
        #expect(center.actionTitle == "Update to 1.4")
    }

    @Test("User attention clears the dot and keeps the update on offer")
    func attentionClearsDotOnly() {
        let (center, driver) = started()
        driver.emit(.reminderHandedToApp(version: "1.3", checkedAt: Self.found))
        driver.emit(.userAttended)
        #expect(!center.showsIndicator)
        #expect(center.state == .available(version: "1.3"))
    }

    @Test("Remind Me Later keeps the title, Skip returns to idle, Install changes nothing")
    func dialogChoices() {
        let last = Date(timeIntervalSince1970: 500)
        let (center, driver) = started(lastCheck: last)
        driver.emit(.reminderHandedToApp(version: "1.3", checkedAt: Self.found))

        driver.emit(.userChose(.dismiss))
        #expect(!center.showsIndicator)
        #expect(center.actionTitle == "Update to 1.3")

        driver.emit(.userChose(.install))
        #expect(center.state == .available(version: "1.3"))

        driver.emit(.userChose(.skip))
        #expect(center.state == .idle(lastChecked: Self.found), "the find is itself a completed check")
        #expect(center.actionTitle == "Check for Updates")
        #expect(center.statusText(now: Self.found) == "up to date · checked just now")
    }

    @Test("A find on a copy that never completed a check still dates the row")
    func findCountsAsACheck() {
        let (center, driver) = started()
        driver.emit(.checkStarted(userInitiated: false))
        driver.emit(.reminderHandedToApp(version: "1.3", checkedAt: Self.found))
        driver.emit(.userChose(.skip))
        #expect(center.state == .idle(lastChecked: Self.found), "never 'not checked yet' after a find")
    }

    @Test("A finished session ends a check but never forgets an update still on offer")
    func sessionFinished() {
        let (center, driver) = started()
        driver.emit(.checkStarted(userInitiated: true))
        driver.emit(.noUpdate(checkedAt: Date(timeIntervalSince1970: 42)))
        driver.emit(.sessionFinished)
        #expect(center.state == .idle(lastChecked: Date(timeIntervalSince1970: 42)))

        driver.emit(.checkStarted(userInitiated: false))
        driver.emit(.sessionFinished)
        #expect(center.state == .idle(lastChecked: Date(timeIntervalSince1970: 42)), "an aborted check falls back to the last completed one")

        driver.emit(.reminderHandedToApp(version: "1.3", checkedAt: Self.found))
        driver.emit(.sessionFinished)
        #expect(center.state == .available(version: "1.3"))
        #expect(!center.showsIndicator)
    }

    @Test("A quiet re-check that fails leaves an update still on offer")
    func scheduledFailureKeepsOffer() {
        let (center, driver) = started()
        driver.emit(.reminderHandedToApp(version: "1.3", checkedAt: Self.found))
        driver.emit(.userChose(.dismiss))
        driver.emit(.sessionFinished)

        // The next day, offline. Nothing about this may hide the update the user asked to be
        // reminded about.
        driver.emit(.checkStarted(userInitiated: false))
        #expect(center.state == .available(version: "1.3"))
        driver.emit(.failed(code: 2001, userInitiated: false))
        driver.emit(.sessionFinished)
        #expect(center.state == .available(version: "1.3"))
        #expect(center.actionTitle == "Update to 1.3")
        #expect(!center.showsIndicator)
    }

    @Test("An install the user started and that failed says so, even from a quiet find")
    func failedInstallAfterQuietFind() {
        let (center, driver) = started()
        driver.emit(.reminderHandedToApp(version: "1.3", checkedAt: Self.found))
        // The driver marks the re-focus user-initiated, so the install failure is not swallowed
        // by the rules that keep a scheduled check quiet.
        driver.emit(.failed(code: 3001, userInitiated: true))
        #expect(center.statusText() == "the update couldn't be installed · download it from GitHub")
    }

    @Test("Status copy for an idle centre")
    func idleCopy() {
        let (center, driver) = started()
        #expect(center.statusText() == "not checked yet")
        let checked = Date(timeIntervalSince1970: 10_000)
        driver.emit(.noUpdate(checkedAt: checked))
        #expect(center.statusText(now: checked.addingTimeInterval(3 * 3600)) == "up to date · checked 3 h ago")
    }

    @Test("A scheduled failure leaves the row alone; a user-initiated one is shown")
    func failuresByOrigin() {
        let last = Date(timeIntervalSince1970: 7)
        let (center, driver) = started(lastCheck: last)

        driver.emit(.checkStarted(userInitiated: false))
        driver.emit(.failed(code: 2001, userInitiated: false))
        #expect(center.state == .idle(lastChecked: last), "an offline daily check must not pin an error for a day")

        driver.emit(.checkStarted(userInitiated: true))
        driver.emit(.failed(code: 2001, userInitiated: true))
        #expect(center.state == .failed(message: "couldn't reach GitHub · try again later"))

        driver.emit(.checkStarted(userInitiated: false))
        driver.emit(.failed(code: 1005, userInitiated: false))
        #expect(center.state == .failed(message: "move Notchboard to Applications to update"),
                "translocation is persistent and actionable, so even a scheduled check says so")
    }

    private static let failureCopy: [(code: Int, expected: String)] = [
        (1003, "move Notchboard to Applications to update"),
        (1005, "move Notchboard to Applications to update"),
        (1002, "couldn't reach GitHub · try again later"),
        (2001, "couldn't reach GitHub · try again later"),
        (3001, "the update couldn't be installed · download it from GitHub"),
        (4012, "the update couldn't be installed · download it from GitHub"),
        (999, "update check failed · try again later"),
    ]

    @Test("Failure copy per Sparkle error code", arguments: failureCopy)
    func failureMessages(code: Int, expected: String) {
        #expect(UpdateCenter.failureMessage(code: code) == expected)
    }

    @Test("Aborts that are not failures produce no event", arguments: [1001, 4007, 4008])
    func nonFailureAborts(code: Int) {
        #expect(SparkleUpdateDriver.event(forAbortCode: code, userInitiated: true) == nil)
    }

    @Test("A real abort becomes a failed event carrying its origin")
    func realAbort() {
        #expect(SparkleUpdateDriver.event(forAbortCode: 2001, userInitiated: false) == .failed(code: 2001, userInitiated: false))
    }

    @Test("The toggle writes through to the driver and the mirror follows the driver, not the tap")
    func toggleWriteThrough() {
        let (center, driver) = started()
        center.setAutomaticallyChecks(false)
        #expect(!driver.automaticallyChecks)
        #expect(!center.automaticallyChecks)
        center.setAutomaticallyChecks(true)
        #expect(center.automaticallyChecks)
    }

    @Test("Checking is a no-op until Sparkle says it can check")
    func checkGatedOnCanCheck() {
        let driver = FakeUpdateDriver()
        let center = UpdateCenter(provenance: Self.release, driver: driver)
        center.checkForUpdates()
        #expect(driver.checkCount == 0)
        center.start()
        driver.emit(.canCheckChanged(false))
        center.checkForUpdates()
        #expect(driver.checkCount == 0)
        driver.emit(.canCheckChanged(true))
        center.checkForUpdates()
        #expect(driver.checkCount == 1)
    }

    @Test("The panel yields while Sparkle has a window up")
    func presentingUI() {
        let (center, driver) = started()
        #expect(!center.isPresentingUpdateUI)
        driver.emit(.updateUIVisible(true))
        #expect(center.isPresentingUpdateUI)
        driver.emit(.sessionFinished)
        #expect(!center.isPresentingUpdateUI)
    }

    private static let ages: [(seconds: Double, expected: String)] = [
        (30, "just now"), (12 * 60, "12 min ago"), (3 * 3600, "3 h ago"),
        (30 * 3600, "yesterday"), (4 * 86400, "4 days ago"),
    ]

    @Test("Relative age copy", arguments: ages)
    func relativeAge(seconds: Double, expected: String) {
        let then = Date(timeIntervalSince1970: 0)
        #expect(UpdateCenter.relativeAge(from: then, to: then.addingTimeInterval(seconds)) == expected)
    }

    @Test("Copy rules: no ellipsis in action titles, never the word claim")
    func copyRules() {
        let (center, driver) = started()
        var seen: [String] = [center.actionTitle, center.statusText()]
        driver.emit(.reminderHandedToApp(version: "1.3", checkedAt: Self.found))
        seen += [center.actionTitle, center.statusText()]
        for code in [1005, 2001, 3001, 999] { seen.append(UpdateCenter.failureMessage(code: code)) }
        seen.append(UpdateCenter(provenance: Self.selfBuilt, driver: nil).statusText())
        #expect(!center.actionTitle.contains("…"))
        #expect(!"Check for Updates".contains("…"))
        #expect(seen.allSatisfy { !$0.lowercased().contains("claim") })
    }
}
