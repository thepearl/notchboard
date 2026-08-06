//
//  ElementRowView.swift
//  notchboard
//

import SwiftUI

struct ElementRowView: View {
    @Bindable var viewModel: NotchboardViewModel
    let element: NBElement
    var isKeyboardSelected: Bool = false

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.toggleFavorite(element.id)
            } label: {
                // The sizing lives inside the label, not on the Button: a frame applied
                // outside enlarges the layout slot without enlarging the hit area, so the
                // star was only clickable on the glyph itself.
                Text(element.isFavorite ? "★" : "☆")
                    .font(NBFont.mono(10))
                    .foregroundStyle(element.isFavorite ? NBColor.amber : NBColor.textMuted)
                    .frame(width: 16, height: 22)
            }
            .buttonStyle(.nbPlain)

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
                    ageLabel: claim.ageLabel,
                    envLabel: element.env.rawValue.lowercased(),
                    // Only the user's own claims are swept by auto-release; teammates'
                    // mock claims never release, and a countdown for them was a lie.
                    autoReleaseIn: claim.who == "you" ? max(0, viewModel.autoReleaseMinutes - claim.minutesAgo) : nil,
                    isShowingTip: viewModel.tooltipElementID == element.id,
                    onEnter: { viewModel.showClaimTooltip(element.id) },
                    onLeave: { viewModel.scheduleClaimTooltipDismissal() },
                    onPopoverHover: { inside in
                        if inside {
                            viewModel.cancelClaimTooltipDismissal()
                        } else {
                            viewModel.scheduleClaimTooltipDismissal()
                        }
                    },
                    onDismiss: { viewModel.dismissClaimTooltip() },
                    onNotify: {
                        viewModel.notifyWhenFree(element)
                        viewModel.dismissClaimTooltip()
                    }
                )
            }

            Text(element.env.rawValue)
                .font(NBFont.mono(8))
                .foregroundStyle(element.env.color)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(element.env.color.opacity(0.35), lineWidth: 1))

            Button {
                viewModel.copyPrimaryField(of: element)
            } label: {
                // Padding and border inside the label so the whole bordered box is the hit
                // target. Applied outside the Button (as they were) they drew a box larger
                // than the button, leaving most of the visible control dead.
                Text("⧉")
                    .font(NBFont.mono(9))
                    .foregroundStyle(NBColor.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(NBColor.border, lineWidth: 1))
            }
            .buttonStyle(.nbPlain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 11)
        .background((hovering || isKeyboardSelected) ? NBColor.rowHover : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius)
                .stroke(isKeyboardSelected ? NBColor.amber.opacity(0.6) : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
        .contentShape(Rectangle())
        .onTapGesture { viewModel.openDetail(element) }
        .onHover { hovering = $0 }
    }
}

private struct ClaimBadge: View {
    let who: String
    let ageLabel: String
    let envLabel: String
    /// Nil for teammates' claims — only the user's own claims actually auto-release.
    let autoReleaseIn: Int?
    let isShowingTip: Bool
    let onEnter: () -> Void
    let onLeave: () -> Void
    let onPopoverHover: (Bool) -> Void
    let onDismiss: () -> Void
    let onNotify: () -> Void

    /// Drives the pulse, and only runs while the badge is hovered — see the note below.
    @State private var pulse = false
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(NBColor.green)
                .frame(width: 6, height: 6)
                .shadow(color: NBColor.green.opacity(0.7), radius: 5)
                // The claim dot pulses on hover and sits at a steady glow otherwise.
                //
                // It used to pulse continuously, which cost ~20% of a CPU core for as long
                // as the panel was open (measured; ~30% with the old animated shadow
                // radius, 0.1% with no animation at all). The cause is structural rather
                // than a bad animation: the panel is a *transparent* borderless window, so
                // every animation frame makes the window server re-blend the whole
                // 404x592 panel — and its 70pt drop shadow — against the desktop behind
                // it. Any continuous animation in this window costs that, so none should
                // run at rest. Hover is when "this claim is live" actually needs saying,
                // and the user is looking right at it.
                .opacity(pulse ? 1 : 0.5)
                .animation(
                    isHovering
                        ? .easeInOut(duration: 1).repeatForever(autoreverses: true)
                        : .easeOut(duration: 0.2),
                    value: pulse
                )
            Text(who)
                .font(NBFont.mono(8.5))
                .foregroundStyle(NBColor.green)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(NBColor.green.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(NBColor.green.opacity(0.25), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
        .onHover { hovering in
            isHovering = hovering
            pulse = hovering
            if hovering { onEnter() } else { onLeave() }
        }
        // A real two-way binding: SwiftUI-initiated dismissals (click elsewhere, Esc) must
        // write back into the view model, or its state desyncs from what's on screen.
        .popover(isPresented: Binding(
            get: { isShowingTip },
            set: { presented in if !presented { onDismiss() } }
        ), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text(who)
                    .font(NBFont.ui(11, weight: .semibold))
                    .foregroundStyle(NBColor.textPrimaryAlt)
                Text("claimed \(ageLabel) · \(envLabel)")
                    .font(NBFont.mono(8.5))
                    .foregroundStyle(NBColor.green)
                if let autoReleaseIn {
                    Text("auto-release: \(autoReleaseIn)m idle")
                        .font(NBFont.mono(8.5))
                        .foregroundStyle(NBColor.textSecondary)
                }
                Button(action: onNotify) {
                    Text("notify when free")
                        .font(NBFont.mono(8.5))
                        .foregroundStyle(NBColor.amber)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(NBColor.amber.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.nbPlain)
                .padding(.top, 2)
            }
            .padding(11)
            .frame(width: 180)
            .background(NBColor.chip)
            // Hovering the popover itself keeps it open — the cursor has to cross from the
            // badge into the popover to reach the notify button.
            .onHover(perform: onPopoverHover)
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
