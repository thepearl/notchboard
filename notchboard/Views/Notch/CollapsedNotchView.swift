//
//  CollapsedNotchView.swift
//  notchboard
//
//  The slim vertical tab that stays docked to the Simulator window's edge when the
//  panel is collapsed. Deliberately minimal after two rounds of team feedback: counts up
//  here weren't worth glancing at, so it shows exactly two things — the connection dot
//  (amber local, green live, red unreachable) and the expand chevron. Zero animation at
//  rest (CLAUDE.md).
//

import SwiftUI

struct CollapsedNotchView: View {
    var edge: NBDockEdge = .right
    /// The room connection colour (NBColor.syncState) — one token with the header's dot
    /// so the two surfaces can't disagree. Amber when there is no room, exactly as before.
    var syncColor: Color = NBColor.amber
    let onTap: () -> Void

    @State private var isHovering = false

    /// The flat side faces the Simulator window; only the outward corners round, and the
    /// shadow falls away from the window. Docked right of Simulator that means flat
    /// leading / rounded trailing; docked left it's mirrored.
    private var notchShape: UnevenRoundedRectangle {
        edge == .right
            ? UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 6, topTrailingRadius: 6)
            : UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6, bottomTrailingRadius: 0, topTrailingRadius: 0)
    }

    var body: some View {
        // Dot and chevron sit together, centred — the stretched-apart version wasted
        // height on nothing (team feedback), so the notch shrank to fit them.
        VStack(spacing: 10) {
            Rectangle()
                .fill(syncColor)
                .frame(width: 11, height: 11)
                .help("room connection — amber local, green live, red unreachable")

            Text(edge == .right ? "»" : "«")
                .font(NBFont.mono(12))
                .foregroundStyle(isHovering ? NBColor.textPrimaryAlt : NBColor.textSecondary)
        }
        .frame(width: NBMetrics.notchWidth, height: NBMetrics.notchHeight)
        .background(isHovering ? NBColor.rowHover : NBColor.chip.opacity(0.9))
        .overlay(notchShape.stroke(isHovering ? NBColor.borderStrong : NBColor.border, lineWidth: 1))
        .clipShape(notchShape)
        .shadow(color: .black.opacity(0.5), radius: 24, x: edge == .right ? 6 : -6, y: 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .help("open notchboard")
    }
}

#Preview("Docked right, room live") {
    ZStack {
        NBColor.background
        CollapsedNotchView(syncColor: NBColor.green, onTap: {})
    }
    .frame(width: 200, height: 220)
}

#Preview("Docked left, local") {
    ZStack {
        NBColor.background
        CollapsedNotchView(edge: .left, onTap: {})
    }
    .frame(width: 200, height: 220)
}
