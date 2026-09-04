//
//  BuildProvenance.swift
//  notchboard
//
//  What build am I? Answered once at launch from the bundle and its code signature, so the
//  updater can refuse to run on a copy it must not touch (vision.md §13.20).
//
//  A copy built from source is ad-hoc signed: its designated requirement is the binary's own
//  hash, with no team identifier. Sparkle would replace such a copy with the Developer ID
//  release without complaint (a valid EdDSA signature over the archive is enough for it), and
//  macOS would then see a different application: the Accessibility grant and every Keychain
//  ACL are bound to the old identity and silently stop applying. So the updater only runs when
//  the running bundle carries the release team, and a self-built copy is told to update by
//  rebuilding.
//

import Foundation
import Security

struct BuildProvenance: Equatable {
    /// The team every release is signed with by release.yml. This is a provenance check, not a
    /// signing setting (those stay team-less so a fresh clone builds with no Apple account):
    /// a fork's own Developer ID build would otherwise fetch our feed and be replaced by our
    /// release, which is exactly the identity swap the gate exists to prevent.
    static let releaseTeamIdentifier = "D8L4KTPGCD"

    /// CFBundleShortVersionString, the version people see ("1.2").
    let installedVersion: String
    /// CFBundleVersion, the number Sparkle compares. Frozen at 1 in the project; release.sh
    /// stamps the real one on release builds.
    let buildNumber: String
    /// nil for an ad-hoc or unsigned bundle.
    let teamIdentifier: String?

    var isSelfBuilt: Bool { teamIdentifier != Self.releaseTeamIdentifier }

    static func current(bundle: Bundle = .main) -> BuildProvenance {
        let info = bundle.infoDictionary ?? [:]
        return BuildProvenance(
            installedVersion: info["CFBundleShortVersionString"] as? String ?? "0",
            buildNumber: info["CFBundleVersion"] as? String ?? "0",
            teamIdentifier: teamIdentifier(ofBundleAt: bundle.bundleURL)
        )
    }

    /// Reads the team identifier out of a bundle's code signature. Every failure (an unsigned
    /// bundle from a CODE_SIGNING_ALLOWED=NO build, an unreadable signature) reads as nil,
    /// which callers treat as self-built. Read-only and cheap; called once at launch.
    static func teamIdentifier(ofBundleAt url: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return nil }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &information) == errSecSuccess,
              let dictionary = information as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
