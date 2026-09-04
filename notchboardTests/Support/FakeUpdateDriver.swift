//
//  FakeUpdateDriver.swift
//  notchboardTests
//
//  The UpdateDriver the tests drive by hand, the way LoopbackTransport stands in for MQTT: it
//  records what the centre asked of it and lets a test emit any Sparkle event in any order.
//

import Foundation
@testable import notchboard

@MainActor
final class FakeUpdateDriver: UpdateDriver {
    var onEvent: ((UpdateEvent) -> Void)?
    var lastUpdateCheckDate: Date?
    private(set) var automaticallyChecks = true
    private(set) var startCount = 0
    private(set) var checkCount = 0

    init(lastUpdateCheckDate: Date? = nil) {
        self.lastUpdateCheckDate = lastUpdateCheckDate
    }

    func start() {
        startCount += 1
        onEvent?(.canCheckChanged(true))
        onEvent?(.automaticChecksChanged(automaticallyChecks))
    }

    func checkForUpdates() {
        checkCount += 1
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        automaticallyChecks = enabled
        onEvent?(.automaticChecksChanged(enabled))
    }

    func emit(_ event: UpdateEvent) {
        onEvent?(event)
    }
}
