//
//  NBColor.swift
//  notchboard
//
//  Design system colors — "dev-tool carbon" direction (locked in explorations doc).
//

import SwiftUI

/// Notchboard's color palette. Values are transcribed 1:1 from the interactive prototype
/// (`Notchboard Prototype.dc.html`) so the native build matches the validated visual direction.
enum NBColor {
    // MARK: Backgrounds
    static let background = Color(hex: 0x0c0e11)
    static let panel = Color(hex: 0x111318)
    static let field = Color(hex: 0x0d0f13)
    static let rowHover = Color(hex: 0x171a20)
    static let chip = Color(hex: 0x15181d)

    // MARK: Borders
    static let borderSubtle = Color(hex: 0x23262d)
    static let border = Color(hex: 0x2a2e37)
    static let borderStrong = Color(hex: 0x3a3f4a)
    static let headerBorder = Color(hex: 0x1d2027)

    // MARK: Text
    //
    // The greys were lifted on 2026-08-07 for legibility: the prototype's values
    // (secondary 0x5b6270, muted 0x464d5a) sat at roughly 2.5:1 against the panel, which
    // is below WCAG AA even for large text, and field labels were genuinely hard to read
    // for someone with no sight problems at all. Every step below now clears 4.5:1
    // against the panel/field backgrounds while keeping the carbon direction — this is a
    // grey scale that reads, not a brighter palette.
    static let textPrimary = Color(hex: 0xf0efec)
    static let textPrimaryAlt = Color(hex: 0xe8e7e3)
    static let textSecondary = Color(hex: 0x8b93a2)
    static let textSecondaryAlt = Color(hex: 0xa9b1bf)
    static let textMuted = Color(hex: 0x7f8797)
    static let textDim = Color(hex: 0x99a1b0)
    static let textFieldValue = Color(hex: 0xd6d4cf)

    // MARK: Accents
    static let amber = Color(hex: 0xffb454)
    static let green = Color(hex: 0x3ddc84)
    static let red = Color(hex: 0xff6b6b)

    /// The brand square doubles as the room connection dot (header + collapsed notch):
    /// no room keeps the familiar amber, a live room turns it green, a failure turns it
    /// red. One mapping for both surfaces so they can't disagree. Static colour only —
    /// the no-continuous-animation constraint applies to it like everything else.
    static func syncState(_ state: SyncConnectionState?) -> Color {
        switch state {
        case nil, .connecting, .disconnected: return amber
        case .connected: return green
        case .failed: return red
        }
    }

    // MARK: Environment colors
    static let envDev = Color(hex: 0x7ab8ff)
    static let envStg = Color(hex: 0xffb454)
    static let envPrd = Color(hex: 0xff6b6b)

    // MARK: Field-type colors (new group / add element)
    static let typeText = Color(hex: 0x7ab8ff)
    static let typeSecret = Color(hex: 0xff6b6b)
    static let typeNumber = Color(hex: 0xc9a3ff)
    static let typeBool = Color(hex: 0x3ddc84)
    static let typeDate = Color(hex: 0xffb787)
    static let typeUrl = Color(hex: 0x7ab8ff)
    static let typePicker = Color(hex: 0xffd27a)

    // MARK: Brand avatar colors (team member avatars in onboarding)
    static let memberPurple = Color(hex: 0x6d5ce6)
    static let memberPink = Color(hex: 0xd65c8b)
    static let memberTeal = Color(hex: 0x3a8f6d)

    // MARK: Onboarding title bar (fake macOS window chrome)
    static let titleBar = Color(hex: 0x17191d)
    static let trafficRed = Color(hex: 0xff5f57)
    static let trafficAmber = Color(hex: 0xfebc2e)
    static let trafficGreen = Color(hex: 0x28c840)
}

extension Color {
    /// Convenience initializer from a 24-bit hex value, e.g. `Color(hex: 0xffb454)`.
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xff) / 255
        let g = Double((hex >> 8) & 0xff) / 255
        let b = Double(hex & 0xff) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}
