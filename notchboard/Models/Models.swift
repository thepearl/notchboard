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
    var minutesAgo: Int
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
