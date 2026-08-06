//
//  CollapsedNotchView.swift
//  notchboard
//
//  The slim vertical tab that stays docked to the Simulator window's edge when the
//  panel is collapsed. Amber glyph + pulsing claim-count readout.
//

import SwiftUI

struct CollapsedNotchView: View {
    let claimedCount: Int
    var edge: NBDockEdge = .right
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
        VStack(spacing: 7) {
            Rectangle()
                .fill(NBColor.amber)
                .frame(width: 9, height: 9)

            Text("●\(claimedCount)")
                .font(NBFont.mono(9, weight: .medium))
                .foregroundStyle(NBColor.green)
                .rotationEffect(.degrees(90))
                .fixedSize()
                .frame(width: 12)

            Text(edge == .right ? "»" : "«")
                .font(NBFont.mono(9))
                .foregroundStyle(NBColor.textSecondary)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 7)
        .background(isHovering ? NBColor.rowHover : NBColor.chip.opacity(0.9))
        .overlay(notchShape.stroke(isHovering ? NBColor.borderStrong : NBColor.border, lineWidth: 1))
        .clipShape(notchShape)
        .shadow(color: .black.opacity(0.5), radius: 24, x: edge == .right ? 6 : -6, y: 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

#Preview("Docked right") {
    ZStack {
        NBColor.background
        CollapsedNotchView(claimedCount: 3, onTap: {})
    }
    .frame(width: 200, height: 260)
}

#Preview("Docked left") {
    ZStack {
        NBColor.background
        CollapsedNotchView(claimedCount: 3, edge: .left, onTap: {})
    }
    .frame(width: 200, height: 260)
}
