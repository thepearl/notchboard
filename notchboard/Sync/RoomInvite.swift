//
//  RoomInvite.swift
//  notchboard
//
//  The invitation is one paste-able line, not a file (vision.md §14.3, revised
//  2026-08-08): the room already holds the whole catalogue as retained messages, so a
//  joiner needs exactly the address and the room password. The invite carries the
//  address half — broker URL (with the shared account's username), room slug, and the
//  broker account's password sealed under the room key — and the room password travels
//  out of band, like wifi.
//
//  Format: "notchboard-room:" + base64url(NBRoomConfig as JSON). A paste-code, not a
//  notchboard:// URL, on purpose: it needs no LaunchServices registration (the Info.plist
//  is generated), survives Slack/email/anything, and can't be triggered by a stray click.
//  An invite that doesn't decode is refused loudly, never guessed at — the same posture
//  as imports (§14.5.5: refuse, don't migrate).
//

import Foundation

/// Main-actor like its callers (dialogs, onboarding, the view model) — unlike RoomCrypto
/// there is no expensive work here to justify fighting NBRoomConfig's default isolation.
enum RoomInvite {

    static let prefix = "notchboard-room:"

    /// One line safe to paste anywhere. `firstSyncCompleted` is forced false — it is this
    /// Mac's history, and an invitee has never merged (same rule as exports).
    static func encode(_ config: NBRoomConfig) -> String? {
        var travelling = config
        travelling.firstSyncCompleted = false
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let json = try? encoder.encode(travelling) else { return nil }
        return prefix + base64URL(json)
    }

    /// Tolerant of the mess pasting produces (whitespace, surrounding newlines), strict
    /// about everything else. nil = not an invite this build understands.
    static func decode(_ raw: String) -> NBRoomConfig? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }
        guard let json = dataFromBase64URL(String(trimmed.dropFirst(prefix.count))),
              var config = try? JSONDecoder().decode(NBRoomConfig.self, from: json),
              config.brokerHost != nil,
              NBRoomConfig.normalisedSlug(config.room) == config.room else { return nil }
        config.firstSyncCompleted = false
        return config
    }

    // MARK: base64url (RFC 4648 §5, unpadded — Slack linkifies "+" and "/" badly)

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func dataFromBase64URL(_ text: String) -> Data? {
        var base64 = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        return Data(base64Encoded: base64)
    }
}
