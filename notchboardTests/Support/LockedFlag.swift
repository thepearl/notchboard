//
//  LockedFlag.swift
//  notchboardTests
//
//  One-shot flag so a continuation can't be resumed twice (completion + timeout racing).
//  Shared by both deeplink integration suites (simctl and adb), which race a real child
//  process against a deadline in exactly the same way.
//

import Foundation

final class LockedFlag: @unchecked Sendable {
    private var used = false
    private let lock = NSLock()

    func setOnce() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}
