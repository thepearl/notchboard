//
//  BuildProvenanceTests.swift
//  notchboardTests
//
//  The test target is hosted by the app, so `Bundle.main` is the ad-hoc built app: exactly the
//  self-built copy the updater must refuse to run on. The version checks keep the four
//  MARKETING_VERSION lines in the project agreeing with each other and with the two-component
//  scheme both Sparkle's build number and Homebrew's bundle comparison rely on.
//

import Foundation
import Testing
@testable import notchboard

@Suite("Build provenance")
@MainActor
struct BuildProvenanceTests {

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // notchboardTests
            .deletingLastPathComponent() // repo root
    }

    private func marketingVersions() throws -> [String] {
        let pbxproj = repoRoot.appendingPathComponent("notchboard.xcodeproj/project.pbxproj")
        let text = try String(contentsOf: pbxproj, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"MARKETING_VERSION = ([^;]+);"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    @Test("The hosted test app is ad-hoc signed, so it reads as built from source")
    func hostIsSelfBuilt() {
        let provenance = BuildProvenance.current()
        #expect(provenance.teamIdentifier == nil)
        #expect(provenance.isSelfBuilt)
    }

    @Test("Only the release team turns the updater on")
    func gateIsTheReleaseTeam() {
        let release = BuildProvenance(installedVersion: "1.2", buildNumber: "1", teamIdentifier: BuildProvenance.releaseTeamIdentifier)
        let fork = BuildProvenance(installedVersion: "1.2", buildNumber: "1", teamIdentifier: "ABCDEF1234")
        let adHoc = BuildProvenance(installedVersion: "1.2", buildNumber: "1", teamIdentifier: nil)
        #expect(!release.isSelfBuilt)
        #expect(fork.isSelfBuilt)
        #expect(adHoc.isSelfBuilt)
    }

    @Test("An unreadable bundle has no team")
    func missingBundleHasNoTeam() {
        let missing = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).app")
        #expect(BuildProvenance.teamIdentifier(ofBundleAt: missing) == nil)
    }

    @Test("The installed version is the project's MARKETING_VERSION, in all four places")
    func versionMatchesProject() throws {
        let versions = try marketingVersions()
        try #require(versions.count == 4, "expected four MARKETING_VERSION lines, found \(versions.count)")
        #expect(Set(versions).count == 1, "the app and test targets disagree: \(versions)")
        #expect(BuildProvenance.current().installedVersion == versions[0])
    }

    @Test("Versions stay two numeric components")
    func versionIsTwoComponents() throws {
        let version = BuildProvenance.current().installedVersion
        let parts = version.split(separator: ".")
        #expect(parts.count == 2, "\(version) is not MAJOR.MINOR")
        #expect(parts.allSatisfy { Int($0) != nil })
    }

    @Test("The build number is an integer Sparkle can compare")
    func buildNumberIsInteger() {
        #expect(Int(BuildProvenance.current().buildNumber) != nil)
    }
}
