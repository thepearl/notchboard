//
//  AwaitCompletionTests.swift
//  notchboardTests
//
//  The quit path waits for every room goodbye to leave its socket, capped so a dead broker
//  cannot hold the process (vision.md §13.20, AppDelegate.applicationShouldTerminate). The cap
//  is the whole point, and the obvious racing task group does not provide one: it awaits every
//  child before returning. These tests hold that seam.
//

import Foundation
import Testing
@testable import notchboard

@Suite("Bounded wait for a goodbye")
struct AwaitCompletionTests {

    @Test("The deadline returns even though the task is still running")
    func deadlineWins() async {
        let slow = Task<Void, Never> { try? await Task.sleep(for: .seconds(30)) }
        defer { slow.cancel() }

        let start = ContinuousClock.now
        await awaitCompletion(of: slow, until: .now + .milliseconds(100))
        let waited = ContinuousClock.now - start

        #expect(waited < .seconds(5), "the cap must bound the wait, not the task")
        #expect(!slow.isCancelled, "waiting must not cancel the goodbye it gave up on")
    }

    @Test("A task that finishes first returns before the deadline")
    func taskWins() async {
        let quick = Task<Void, Never> {}
        let start = ContinuousClock.now
        await awaitCompletion(of: quick, until: .now + .seconds(30))
        #expect(ContinuousClock.now - start < .seconds(5), "a finished goodbye must not wait for the cap")
    }
}
