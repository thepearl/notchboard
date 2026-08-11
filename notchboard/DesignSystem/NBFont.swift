//
//  NBFont.swift
//  notchboard
//
//  Typography — Space Grotesk for headers/UI, JetBrains Mono for data & badges.
//
//  Both are bundled with the app and registered on first use by NBBundledFonts, so these names
//  resolve on any machine rather than only on one with the fonts installed. If registration is
//  ever refused, `.custom` falls back to the system font on its own.
//

import SwiftUI

enum NBFont {
    /// Headers, names, and general UI copy.
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        NBBundledFonts.register()
        return .custom(NBBundledFonts.uiFamily, size: size, relativeTo: .body)
            .weight(weight)
    }

    /// Data, keys, badges, and technical/monospace microcopy.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        NBBundledFonts.register()
        return .custom(NBBundledFonts.monoFamily, size: size, relativeTo: .body)
            .weight(weight)
    }
}

/// Reusable text-style presets mirroring the prototype's recurring type combinations.
///
/// The default label size went 8 → 9.5 in the same legibility pass as NBColor's greys:
/// 8pt mono with 0.6 tracking is a caption, and these are the labels naming every field
/// in the app.
extension View {
    func nbMonoLabel(_ size: CGFloat = 10.5, color: Color = NBColor.textMuted, tracking: CGFloat = 0.6) -> some View {
        self.font(NBFont.mono(size, weight: .medium))
            .foregroundStyle(color)
            .tracking(tracking)
    }
}
