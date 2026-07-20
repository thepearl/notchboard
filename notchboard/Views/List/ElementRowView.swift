//
//  ElementRowView.swift
//  notchboard
//

import SwiftUI

struct ElementRowView: View {
    @Bindable var viewModel: NotchboardViewModel
    let element: NBElement

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.toggleFavorite(element.id)
            } label: {
                Text(element.isFavorite ? "★" : "☆")
                    .font(NBFont.mono(10))
                    .foregroundStyle(element.isFavorite ? NBColor.amber : NBColor.textMuted)
            }
            .buttonStyle(.plain)
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 3) {
                Text(element.name)
                    .font(NBFont.ui(12.5, weight: .semibold))
                    .foregroundStyle(NBColor.textPrimaryAlt)
                    .lineLimit(1)
                Text(viewModel.secondaryText(for: element, in: viewModel.activeGroup))
                    .font(NBFont.mono(10))
                    .foregroundStyle(NBColor.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if let claim = element.claimedBy {
                ClaimBadge(
                    who: viewModel.memberName(claim.who),
                    minutesAgo: claim.minutesAgo,
                    envLabel: element.env.rawValue.lowercased(),
                    autoReleaseIn: max(1, viewModel.autoReleaseMinutes - claim.minutesAgo),
                    isShowingTip: viewModel.tooltipElementID == element.id,
                    onEnter: { viewModel.tooltipElementID = element.id },
                    onLeave: { viewModel.tooltipElementID = nil },
                    onNotify: { viewModel.notifyWhenFree(element) }
                )
            }

            Text(element.env.rawValue)
                .font(NBFont.mono(8))
                .foregroundStyle(element.env.color)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(element.env.color.opacity(0.35), lineWidth: 1))

            Button {
                viewModel.copyPrimaryField(of: element)
            } label: {
                Text("⧉")
                    .font(NBFont.mono(9))
            }
            .buttonStyle(.plain)
            .foregroundStyle(NBColor.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(NBColor.border, lineWidth: 1))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 11)
        .background(hovering ? NBColor.rowHover : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .contentShape(Rectangle())
        .onTapGesture { viewModel.openDetail(element) }
        .onHover { hovering = $0 }
    }
}

private struct ClaimBadge: View {
    let who: String
    let minutesAgo: Int
    let envLabel: String
    let autoReleaseIn: Int
    let isShowingTip: Bool
    let onEnter: () -> Void
    let onLeave: () -> Void
    let onNotify: () -> Void

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(NBColor.green)
                .frame(width: 6, height: 6)
                .shadow(color: NBColor.green.opacity(pulse ? 0.9 : 0.5), radius: pulse ? 6 : 3)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                        pulse.toggle()
                    }
                }
            Text(who)
                .font(NBFont.mono(8.5))
                .foregroundStyle(NBColor.green)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(NBColor.green.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(NBColor.green.opacity(0.25), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .onHover { hovering in
            if hovering { onEnter() } else { onLeave() }
        }
        .popover(isPresented: .constant(isShowingTip), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text(who)
                    .font(NBFont.ui(11, weight: .semibold))
                    .foregroundStyle(NBColor.textPrimaryAlt)
                Text("claimed \(minutesAgo)m ago · \(envLabel)")
                    .font(NBFont.mono(8.5))
                    .foregroundStyle(NBColor.green)
                Text("auto-release: \(autoReleaseIn)m idle")
                    .font(NBFont.mono(8.5))
                    .foregroundStyle(NBColor.textSecondary)
                Button(action: onNotify) {
                    Text("notify when free")
                        .font(NBFont.mono(8.5))
                        .foregroundStyle(NBColor.amber)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(NBColor.amber.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(11)
            .frame(width: 180)
            .background(NBColor.chip)
        }
    }
}

struct RowsEmptyStateView: View {
    var body: some View {
        VStack {
            Text("no elements match — clear filters or ＋ add one")
                .font(NBFont.mono(9.5))
                .foregroundStyle(NBColor.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}
