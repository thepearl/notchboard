//
//  SparkleUpdateDriver.swift
//  notchboard
//
//  The production UpdateDriver: Sparkle's standard updater controller with the gentle-reminders
//  delegate (vision.md §13.20). Sparkle keeps its dialog for the install itself; what this class
//  changes is what happens when a scheduled check finds something (nothing visible, the centre
//  gets an event) and how the centre learns what the user did.
//
//  Sparkle's classes and SPUUpdaterDelegate are main-actor in Swift (NS_SWIFT_UI_ACTOR), so those
//  conformances are plain. SPUStandardUserDriverDelegate carries no annotation and is adopted
//  with @preconcurrency, on Sparkle's documented promise to call it on the main thread. Swift 5
//  mode adds no dynamic check of that promise (SE-0423 emits one only under Swift 6), so it is a
//  promise, not an assertion.
//

import AppKit
import Sparkle
import os

@MainActor
final class SparkleUpdateDriver: NSObject, UpdateDriver {
    var onEvent: ((UpdateEvent) -> Void)?

    private var controller: SPUStandardUpdaterController?
    private var observations: [NSKeyValueObservation] = []
    /// Recorded when a check begins so a later abort knows whether Settings may show it.
    private var currentCheckIsUserInitiated = false
    private static let logger = Logger(subsystem: "flourix.notchboard", category: "updates")

    var lastUpdateCheckDate: Date? { controller?.updater.lastUpdateCheckDate }

    /// Creates the controller here rather than in init: a driver that is never started allocates
    /// nothing on Sparkle's side, and there is no self-as-delegate before the object exists.
    /// `startUpdater()` is where Sparkle validates SUPublicEDKey and schedules the first check.
    func start() {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: self
        )
        self.controller = controller
        let updater = controller.updater
        // Hoisted so both handlers fit on one line with their parameters.
        let canCheck = \SPUUpdater.canCheckForUpdates
        let automatic = \SPUUpdater.automaticallyChecksForUpdates
        observations = [
            // KVO handlers are Sendable closures; Sparkle fires them on the main thread, which
            // assumeIsolated checks (the AdbBridge / tracker precedent for off-actor callbacks).
            updater.observe(canCheck, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated {
                    self?.onEvent?(.canCheckChanged(updater.canCheckForUpdates))
                }
            },
            updater.observe(automatic, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated {
                    self?.onEvent?(.automaticChecksChanged(updater.automaticallyChecksForUpdates))
                }
            }
        ]
        controller.startUpdater()
        Self.logger.info("updater started, feed \(updater.feedURL?.host() ?? "unset", privacy: .public)")
    }

    /// Sparkle puts a window up straight away for a user-initiated check (progress, then the
    /// result), or re-focuses the update it was asked not to show earlier. The centre already
    /// gates on `canCheck`; the re-check here covers the tick between KVO and the click, when
    /// Sparkle would silently do nothing and the panel would otherwise stay yielded for good.
    ///
    /// The flag is set here rather than left to `mayPerform`, which only runs for a fresh check:
    /// re-focusing a pending reminder runs no check at all, so an install that then fails would
    /// otherwise be classified as scheduled and swallowed by the quiet rules. A later scheduled
    /// check resets it.
    func checkForUpdates() {
        guard let controller, controller.updater.canCheckForUpdates else { return }
        currentCheckIsUserInitiated = true
        onEvent?(.updateUIVisible(true))
        controller.updater.checkForUpdates()
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    // MARK: - Pure mappings (tested without Sparkle)

    /// Which aborts are failures worth an event. "No update" arrives here as well as through
    /// `updaterDidNotFindUpdate`, and a cancelled or postponed install is the user's own choice.
    static func event(forAbortCode code: Int, userInitiated: Bool) -> UpdateEvent? {
        switch code {
        case 1001, 4007, 4008: return nil
        default: return .failed(code: code, userInitiated: userInitiated)
        }
    }
}

extension SparkleUpdateDriver: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        currentCheckIsUserInitiated = updateCheck == .updates
        onEvent?(.checkStarted(userInitiated: currentCheckIsUserInitiated))
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        onEvent?(.foundUpdate(version: item.displayVersionString, checkedAt: Date()))
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        onEvent?(.noUpdate(checkedAt: Date()))
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let code = (error as NSError).code
        let userInitiated = currentCheckIsUserInitiated
        guard let event = Self.event(forAbortCode: code, userInitiated: userInitiated) else { return }
        Self.logger.error("update check aborted: \(code, privacy: .public)")
        onEvent?(event)
    }

    func updater(
        _ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState
    ) {
        switch choice {
        case .install: onEvent?(.userChose(.install))
        case .dismiss: onEvent?(.userChose(.dismiss))
        case .skip: onEvent?(.userChose(.skip))
        @unknown default: break
        }
    }
}

extension SparkleUpdateDriver: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Never for a scheduled check: the app shows the reminder its own quiet way.
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        if handleShowingUpdate {
            onEvent?(.updateUIVisible(true))
        } else {
            onEvent?(.reminderHandedToApp(version: update.displayVersionString, checkedAt: Date()))
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        onEvent?(.userAttended)
    }

    func standardUserDriverWillFinishUpdateSession() {
        onEvent?(.sessionFinished)
    }
}
