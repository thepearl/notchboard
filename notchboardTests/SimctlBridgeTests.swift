//
//  SimctlBridgeTests.swift
//  notchboardTests
//
//  Guards the redaction rules that keep passwords out of logs and toasts. The argv
//  exposure itself is a documented tradeoff (see DeeplinkBridge header); these tests make
//  sure everything under the app's control stays clean, for both bridges — the helpers
//  are shared plumbing now.
//

import Foundation
import Testing
@testable import notchboard

@Suite("Deeplink redaction")
struct DeeplinkRedactionTests {

    private let url = "myapp://debug/login?user=alice&pass=hunter2"

    @Test("redacted() strips the query entirely")
    func redactedStripsQuery() {
        #expect(DeeplinkBridge.redacted(url) == "myapp://debug/login")
        #expect(!DeeplinkBridge.redacted(url).contains("hunter2"))
    }

    @Test("redacted() leaves a query-less URL alone")
    func redactedNoQuery() {
        #expect(DeeplinkBridge.redacted("myapp://debug/login") == "myapp://debug/login")
    }

    @Test("sanitized() removes an echoed full URL from stderr")
    func sanitizedRemovesFullURL() {
        let stderr = "An error was encountered opening \(url) (code 1)."
        let clean = DeeplinkBridge.sanitized(stderr, url: url)
        #expect(!clean.contains("hunter2"))
        #expect(clean.contains("myapp://debug/login"))
    }

    @Test("sanitized() removes a bare query string from stderr")
    func sanitizedRemovesBareQuery() {
        let stderr = "invalid query: user=alice&pass=hunter2"
        let clean = DeeplinkBridge.sanitized(stderr, url: url)
        #expect(!clean.contains("hunter2"))
    }

    @Test("sanitized() leaves unrelated stderr untouched")
    func sanitizedLeavesUnrelatedText() {
        let stderr = "No devices are booted."
        #expect(DeeplinkBridge.sanitized(stderr, url: url) == stderr)
    }
}
