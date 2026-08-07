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
///
/// The default label size went 8 → 9.5 in the same legibility pass as NBColor's greys:
/// 8pt mono with 0.6 tracking is a caption, and these are the labels naming every field
/// in the app.
extension View {
    func nbMonoLabel(_ size: CGFloat = 9.5, color: Color = NBColor.textMuted, tracking: CGFloat = 0.6) -> some View {
        self.font(NBFont.mono(size, weight: .medium))
            .foregroundStyle(color)
            .tracking(tracking)
    }
}
