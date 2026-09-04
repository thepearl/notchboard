//
//  UpdateDriver.swift
//  notchboard
//
//  The seam between the update centre and Sparkle (vision.md §13.20), shaped like SyncTransport:
//  one protocol, one production driver, one fake in the tests. It earns the abstraction the same
//  way the transport did, because the state rules (which event lights the dot, what a scheduled
//  failure may and may not do to the Settings row, what "Remind Me Later" leaves behind) are
//  exactly the code that must be testable with no network and no Sparkle.
//

import Foundation

/// What the user answered in Sparkle's update dialog.
enum UpdateChoice: Equatable {
    case install
    /// "Remind Me Later": the update is still real and Sparkle offers it again next time.
    case dismiss
    /// "Skip This Version": Sparkle never offers this version again on its own.
    case skip
}

/// Everything the centre needs to hear from a driver. Versions are display strings ("1.3").
enum UpdateEvent: Equatable {
    case canCheckChanged(Bool)
    case automaticChecksChanged(Bool)
    case checkStarted(userInitiated: Bool)
    /// Any check found a newer version. Sparkle shows user-initiated finds itself.
    /// `checkedAt` is what makes a find count as a completed check, like `noUpdate`: without it
    /// "Skip This Version" would leave the row saying a check had never run.
    case foundUpdate(version: String, checkedAt: Date)
    /// A scheduled check found one and Sparkle agreed not to show it: the app owns the
    /// reminder from here (the dot, the Settings row, the menu title).
    case reminderHandedToApp(version: String, checkedAt: Date)
    case noUpdate(checkedAt: Date)
    case failed(code: Int, userInitiated: Bool)
    case userChose(UpdateChoice)
    /// Sparkle has a window up: a user-initiated check, or an update it decided to show.
    case updateUIVisible(Bool)
    case userAttended
    case sessionFinished
}

@MainActor
protocol UpdateDriver: AnyObject {
    var onEvent: ((UpdateEvent) -> Void)? { get set }
    var lastUpdateCheckDate: Date? { get }
    /// Starts the scheduler. Emits the initial `canCheckChanged` and `automaticChecksChanged`.
    func start()
    /// Re-focuses a pending update, or runs a fresh user-initiated check.
    func checkForUpdates()
    /// Write-through to Sparkle's own setting; the driver answers with `.automaticChecksChanged`.
    func setAutomaticallyChecks(_ enabled: Bool)
}
