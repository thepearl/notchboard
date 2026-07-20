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
    let onTap: () -> Void

    @State private var isHovering = false

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

            Text("»")
                .font(NBFont.mono(9))
                .foregroundStyle(NBColor.textSecondary)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 7)
        .background(isHovering ? Color(hex: 0x171a20) : NBColor.chip.opacity(0.9))
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 6, topTrailingRadius: 6)
                .stroke(isHovering ? NBColor.borderStrong : NBColor.border, lineWidth: 1)
        )
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 6, topTrailingRadius: 6))
        .shadow(color: .black.opacity(0.5), radius: 24, x: 6, y: 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

#Preview {
    ZStack {
        NBColor.background
        CollapsedNotchView(claimedCount: 3, onTap: {})
    }
    .frame(width: 200, height: 260)
}
