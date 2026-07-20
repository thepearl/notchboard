//
//  Models.swift
//  notchboard
//
//  Data model transcribed from the prototype's state shape (see vision.md §6).
//

import Foundation
import SwiftUI

enum NBEnvironment: String, CaseIterable, Identifiable, Codable {
    case all = "ALL"
    case dev = "DEV"
    case stg = "STG"
    case prd = "PRD"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .all: return NBColor.textDim
        case .dev: return NBColor.envDev
        case .stg: return NBColor.envStg
        case .prd: return NBColor.envPrd
        }
    }
}

/// Which side of the Simulator window Notchboard docks to.
enum NBDockEdge: String, CaseIterable, Identifiable, Codable {
    case right = "RIGHT"
    case left = "LEFT"

    var id: String { rawValue }
    var label: String { self == .right ? "Right edge" : "Left edge" }
}

enum NBFieldType: String, CaseIterable, Identifiable, Codable {
    case text, secret, number, bool, date, url, picker

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .text: return NBColor.typeText
        case .secret: return NBColor.typeSecret
        case .number: return NBColor.typeNumber
        case .bool: return NBColor.typeBool
        case .date: return NBColor.typeDate
        case .url: return NBColor.typeUrl
        case .picker: return NBColor.typePicker
        }
    }
}

struct NBField: Identifiable, Codable, Equatable {
    let id: UUID
    var key: String
    var label: String
    var type: NBFieldType

    init(id: UUID = UUID(), key: String, label: String, type: NBFieldType) {
        self.id = id
        self.key = key
        self.label = label
        self.type = type
    }
}

struct NBMember: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var short: String
    var avatarColorHex: UInt32

    var avatarColor: Color { Color(hex: avatarColorHex) }

    var initials: String {
        name.split(separator: " ").compactMap { $0.first }.prefix(2).map(String.init).joined().uppercased()
    }
}

struct NBClaim: Codable, Equatable {
    var who: String   // member id, or "you"
    var claimedAt: Date

    /// Live age of the claim — drives the "claimed Xm ago" labels and auto-release.
    var minutesAgo: Int {
        max(0, Int(Date().timeIntervalSince(claimedAt) / 60))
    }

    init(who: String, claimedAt: Date = Date()) {
        self.who = who
        self.claimedAt = claimedAt
    }

    /// Convenience for seed/mock data expressed as "claimed N minutes ago".
    init(who: String, minutesAgo: Int) {
        self.init(who: who, claimedAt: Date().addingTimeInterval(TimeInterval(-minutesAgo * 60)))
    }

    // Custom decoding keeps pre-claimedAt state files (which stored minutesAgo) loadable.
    private enum CodingKeys: String, CodingKey {
        case who, claimedAt, minutesAgo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        who = try container.decode(String.self, forKey: .who)
        if let date = try container.decodeIfPresent(Date.self, forKey: .claimedAt) {
            claimedAt = date
        } else {
            let legacyMinutes = try container.decodeIfPresent(Int.self, forKey: .minutesAgo) ?? 0
            claimedAt = Date().addingTimeInterval(TimeInterval(-legacyMinutes * 60))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(who, forKey: .who)
        try container.encode(claimedAt, forKey: .claimedAt)
    }
}

struct NBElement: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var env: NBEnvironment
    var isFavorite: Bool
    var claimedBy: NBClaim?
    var note: String
    var lastUsed: String
    var values: [String: String]

    var isClaimed: Bool { claimedBy != nil }
}

struct NBGroup: Identifiable, Codable, Equatable {
    var id: String
    var label: String
    var singular: String
    var secondaryKey: String
    var fields: [NBField]
    var elements: [NBElement]
}

struct NBWorkspace: Codable, Equatable {
    var name: String
    var groupOrder: [String]
    var groups: [String: NBGroup]
    var members: [String: NBMember]
    var onlineCount: Int
}
