//
//  EnvironmentFilterView.swift
//  notchboard
//

import SwiftUI

struct EnvironmentFilterView: View {
    @Bindable var viewModel: NotchboardViewModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(NBEnvironment.allCases) { env in
                EnvChip(
                    label: env.rawValue,
                    isActive: viewModel.environmentFilter == env,
                    activeColor: NBColor.amber
                ) {
                    viewModel.environmentFilter = env
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }
}

/// The environment badges on a row or a detail header. An element can live in several at
/// once, so this renders the whole set in a fixed order rather than one value.
struct EnvironmentBadges: View {
    let environments: [NBEnvironment]
    var size: CGFloat = 9

    var body: some View {
        HStack(spacing: 3) {
            ForEach(environments) { env in
                Text(env.rawValue)
                    .font(NBFont.mono(size))
                    .foregroundStyle(env.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius)
                            .stroke(env.color.opacity(0.4), lineWidth: 1)
                    )
            }
        }
    }
}

struct EnvChip: View {
    let label: String
    let isActive: Bool
    var activeColor: Color = NBColor.amber
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Text(label)
            .font(NBFont.mono(10))
            .foregroundStyle(isActive ? activeColor : NBColor.textDim)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(isActive ? activeColor.opacity(0.08) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius)
                    .stroke(hovering ? activeColor : (isActive ? activeColor : NBColor.border), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .onHover { hovering = $0 }
            // Chips carry their own active/hover styling; a system focus ring on top of it
            // just looked like a stray blue rectangle.
            .focusEffectDisabled()
    }
}

#Preview {
    EnvironmentFilterView(viewModel: NotchboardViewModel())
        .background(NBColor.panel)
}
