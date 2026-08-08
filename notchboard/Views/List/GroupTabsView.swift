//
//  GroupTabsView.swift
//  notchboard
//

import SwiftUI

struct GroupTabsView: View {
    @Bindable var viewModel: NotchboardViewModel

    var body: some View {
        HStack(spacing: 3) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(viewModel.workspace.groupOrder, id: \.self) { groupID in
                        if let group = viewModel.workspace.groups[groupID] {
                            GroupTab(
                                label: "\(group.label)·\(group.elements.count)",
                                isActive: viewModel.activeGroupID == groupID
                            ) {
                                viewModel.selectGroup(groupID)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            if !viewModel.activeGroup.id.isEmpty {
                Button(action: viewModel.openEditGroup) {
                    Text("✎")
                        .font(NBFont.ui(12))
                        .foregroundStyle(NBColor.textSecondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.nbPlain)
                .nbHoverColor(NBColor.amber, base: NBColor.textSecondary)
                .help("edit “\(viewModel.activeGroup.label)” (rename, fields, delete)")
            }

            Button(action: viewModel.openNewGroup) {
                Text("＋ new group")
                    .font(NBFont.ui(14))
                    .foregroundStyle(NBColor.textSecondary)
            }
            .buttonStyle(.nbPlain)
            .nbHoverColor(NBColor.amber, base: NBColor.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }
}

private struct GroupTab: View {
    let label: String
    let isActive: Bool
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Text(label)
            .font(NBFont.ui(11.5, weight: isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? NBColor.background : (hovering ? NBColor.textPrimaryAlt : NBColor.textSecondaryAlt))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isActive ? NBColor.amber : Color.clear)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 3))
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .onHover { hovering = $0 }
            .fixedSize()
            .focusEffectDisabled()
    }
}

/// The back affordance shared by the detail, add, and new-group screens.
///
/// The hit area is the whole 26pt square, not the glyph's own bounds. A bare
/// `Text("←")` in a plain-styled Button is only clickable on the arrow's drawn pixels, which
/// made this feel broken — you had to hit the stroke itself.
struct NBBackButton: View {
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("←")
                .font(NBFont.ui(13))
                .foregroundStyle(hovering ? NBColor.textPrimaryAlt : NBColor.textSecondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.nbPlain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .help("back to the list (Esc)")
    }
}

/// Small helper to apply a hover-driven foreground color swap without repeating `@State` boilerplate.
private struct HoverColorModifier: ViewModifier {
    let hoverColor: Color
    let baseColor: Color
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(hovering ? hoverColor : baseColor)
            .onHover { hovering = $0 }
    }
}

extension View {
    func nbHoverColor(_ hover: Color, base: Color) -> some View {
        modifier(HoverColorModifier(hoverColor: hover, baseColor: base))
    }
}

#Preview {
    GroupTabsView(viewModel: NotchboardViewModel())
        .background(NBColor.panel)
}
