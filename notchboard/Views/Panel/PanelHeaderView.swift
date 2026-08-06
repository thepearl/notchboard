//
//  PanelHeaderView.swift
//  notchboard
//

import SwiftUI

struct PanelHeaderView: View {
    let workspaceName: String
    let memberCount: Int
    let onCollapse: () -> Void

    @State private var collapseHovering = false

    var body: some View {
        HStack(spacing: 9) {
            Rectangle()
                .fill(NBColor.amber)
                .frame(width: 8, height: 8)

            Text("notchboard")
                .font(NBFont.ui(13, weight: .bold))
                .foregroundStyle(NBColor.textPrimary)
                .tracking(-0.2)

            Text("/ \(workspaceName)")
                .font(NBFont.mono(9.5))
                .foregroundStyle(NBColor.textSecondary)

            Spacer()

            // Member count, not "online" — presence doesn't exist without a backend, and
            // the header shouldn't pretend it does.
            Text("\(memberCount) members")
                .font(NBFont.mono(9))
                .foregroundStyle(NBColor.textSecondary)

            Button(action: onCollapse) {
                Text("«")
                    .font(NBFont.mono(10))
                    .foregroundStyle(collapseHovering ? NBColor.textPrimaryAlt : NBColor.textSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius)
                            .stroke(collapseHovering ? NBColor.borderStrong : NBColor.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.nbPlain)
            .onHover { collapseHovering = $0 }
            .help("collapse to notch")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(
            Rectangle()
                .fill(Color.clear)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(NBColor.headerBorder).frame(height: 1)
                }
        )
    }
}

#Preview {
    PanelHeaderView(workspaceName: "acme-mobile", memberCount: 4, onCollapse: {})
        .background(NBColor.panel)
}
