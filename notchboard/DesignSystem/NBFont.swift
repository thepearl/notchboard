//
//  NBFont.swift
//  notchboard
//
//  Typography — Space Grotesk for headers/UI, JetBrains Mono for data & badges.
//  Falls back to system fonts if the custom fonts aren't bundled/installed yet.
//

import SwiftUI

enum NBFont {
    /// Headers, names, and general UI copy.
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Space Grotesk", size: size, relativeTo: .body)
            .weight(weight)
    }

    /// Data, keys, badges, and technical/monospace microcopy.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("JetBrains Mono", size: size, relativeTo: .body)
            .weight(weight)
    }
}

/// Reusable text-style presets mirroring the prototype's recurring type combinations.
extension View {
    func nbMonoLabel(_ size: CGFloat = 8, color: Color = NBColor.textMuted, tracking: CGFloat = 0.6) -> some View {
        self.font(NBFont.mono(size, weight: .medium))
            .foregroundStyle(color)
            .tracking(tracking)
    }
}
