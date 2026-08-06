//
//  NBButtonStyle.swift
//  notchboard
//
//  The button style used everywhere in Notchboard, in place of `.plain`.
//

import SwiftUI

/// Use this instead of `.buttonStyle(.nbPlain)`.
///
/// `.plain` hit-tests only the pixels the label actually draws. That is fine for a filled
/// button, but every button in this app draws its shape with a `.frame()` plus a stroked
/// `.overlay()`, and neither of those is hit-testable — so a 80×36 "cancel" button was
/// clickable on the six glyphs of the word "cancel" and dead everywhere else in the box the
/// user can plainly see. Same for the back arrows, the primary amber buttons, and the small
/// icon buttons.
///
/// `contentShape(Rectangle())` makes the label's whole frame the hit region. The press
/// opacity is the other thing `.plain` omits: without it a click gives no feedback at all,
/// which reads as an unresponsive button even when it works.
struct NBPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == NBPlainButtonStyle {
    /// Notchboard's plain button: full-frame hit area plus a press state.
    static var nbPlain: NBPlainButtonStyle { NBPlainButtonStyle() }
}
