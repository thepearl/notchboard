//
//  InfoPlistUpdateKeysTests.swift
//  notchboardTests
//
//  Sparkle's keys live in the merged root Info.plist because INFOPLIST_KEY_ settings only carry
//  Apple's keys (vision.md §13.20). A missing or malformed key does not fail the build: Sparkle
//  would pop its own "Unable to Check For Updates" alert at every launch for every release user.
//  These tests read the built bundle, exactly as Sparkle does, and pin the project settings the
//  release pipeline assumes.
//

import Foundation
import Testing
@testable import notchboard

@Suite("Sparkle Info.plist keys and project pins")
@MainActor
struct InfoPlistUpdateKeysTests {

    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func pbxproj() throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent("notchboard.xcodeproj/project.pbxproj"), encoding: .utf8)
    }

    /// The build-settings block of one configuration of the app target.
    private func configBlock(_ id: String, in text: String) throws -> Substring {
        let start = try #require(text.range(of: "\t\t\(id) /* "), "config \(id) not found")
        let end = try #require(text.range(of: "\t\t};", range: start.upperBound..<text.endIndex))
        return text[start.lowerBound..<end.upperBound]
    }

    @Test("The feed is the GitHub latest-release appcast over https")
    func feedURL() throws {
        let feed = try #require(info["SUFeedURL"] as? String)
        #expect(feed == "https://github.com/thepearl/notchboard/releases/latest/download/appcast.xml")
        let url = try #require(URL(string: feed))
        #expect(url.scheme == "https")
        #expect(url.host() == "github.com")
    }

    @Test("The public key is a 32-byte Ed25519 key")
    func publicKey() throws {
        let key = try #require(info["SUPublicEDKey"] as? String)
        let bytes = try #require(Data(base64Encoded: key))
        #expect(bytes.count == 32)
    }

    @Test("Automatic checks default on, automatic installs are never offered")
    func defaults() throws {
        #expect(try #require(info["SUEnableAutomaticChecks"] as? Bool) == true)
        #expect(try #require(info["SUAllowsAutomaticUpdates"] as? Bool) == false)
    }

    @Test("Only the Debug configuration carries the library-validation entitlement")
    func debugOnlyEntitlements() throws {
        let text = try pbxproj()
        let debug = try configBlock("EA8D352430095900009EED09", in: text)
        let release = try configBlock("EA8D352530095900009EED09", in: text)
        #expect(debug.contains("CODE_SIGN_ENTITLEMENTS = Debug.entitlements;"))
        #expect(!release.contains("CODE_SIGN_ENTITLEMENTS"))
        #expect(release.contains("ENABLE_HARDENED_RUNTIME = YES;"))
    }

    @Test("Debug.entitlements holds the one exception and nothing else")
    func debugEntitlementsContent() throws {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("Debug.entitlements"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        let dict = try #require(plist as? [String: Any])
        #expect(Array(dict.keys) == ["com.apple.security.cs.disable-library-validation"])
        #expect(dict["com.apple.security.cs.disable-library-validation"] as? Bool == true)
    }

    @Test("Sparkle is pinned to the exact version the release job downloads tools for")
    func sparklePinnedExactly() throws {
        let text = try pbxproj()
        let start = try #require(text.range(of: "XCRemoteSwiftPackageReference \"Sparkle\" */ = {"))
        let end = try #require(text.range(of: "\t\t};", range: start.upperBound..<text.endIndex))
        let block = text[start.lowerBound..<end.upperBound]
        #expect(block.contains("kind = exactVersion;"))
        #expect(block.contains("version = 2.9.6;"))
    }
}
