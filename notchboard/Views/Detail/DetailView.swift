//
//  DetailView.swift
//  notchboard
//

import SwiftUI

struct DetailView: View {
    @Bindable var viewModel: NotchboardViewModel
    let element: NBElement

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                fieldsSection
                actionsSection
            }
            .padding(19)
        }
    }

    private var group: NBGroup { viewModel.activeGroup }

    private var claimLine: (text: String, color: Color) {
        if let claim = element.claimedBy {
            let suffix = viewModel.presenceSuffix(for: claim)
            return ("● in use by \(viewModel.memberName(claim.who).lowercased()) · \(claim.ageLabel)\(suffix)",
                    suffix.isEmpty ? NBColor.green : NBColor.textSecondary)
        }
        return ("○ free", NBColor.textSecondary)
    }

    /// Two tight rows (third iteration — one crowded line was noise, but a dedicated
    /// chrome row wasted a whole line on two small buttons and read even worse):
    /// back / name / star / ⋯ share the top line, and the status + badges tuck directly
    /// under the name so the block hangs together.
    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                NBBackButton(action: viewModel.backToList)
                Text(element.name)
                    .font(NBFont.ui(15, weight: .bold))
                    .foregroundStyle(NBColor.textPrimary)
                    .lineLimit(1)
                // The status dot, not the star: green filled = in use, grey outline =
                // free, words in the tooltip. The star still lives on the list rows —
                // up here it competed with the name for no reason (team feedback).
                statusDot
                Spacer()
                elementActionsMenu
            }

            HStack {
                Spacer()
                EnvironmentBadges(environments: element.sortedEnvironments, size: 10)
            }
        }
    }

    private var statusDot: some View {
        Group {
            if element.isClaimed {
                Circle().fill(claimLine.color)
            } else {
                Circle().strokeBorder(NBColor.textSecondary, lineWidth: 1.5)
            }
        }
        .frame(width: 9, height: 9)
        .help(claimLine.text)
    }

    /// Edit and delete live here rather than as a pair of small text buttons at the bottom
    /// of the scroll view, where they read as one two-tone control and cost a screenful of
    /// space. Destructive action stays red and now goes through a real confirmation.
    private var elementActionsMenu: some View {
        Menu {
            Button("edit") { viewModel.openEdit(element) }
            Divider()
            Button("delete…", role: .destructive) {
                let hasSecrets = !group.secretFieldKeys.isEmpty
                if ElementDialogs.confirmDelete(name: element.name, hasSecrets: hasSecrets) {
                    viewModel.deleteElement(element.id)
                }
            }
        } label: {
            Text("⋯")
                .font(NBFont.mono(12, weight: .bold))
                .foregroundStyle(NBColor.textSecondaryAlt)
                .frame(width: 24, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius)
                        .stroke(NBColor.border, lineWidth: 1)
                )
        }
        .menuStyle(.button)
        .buttonStyle(.nbPlain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("edit or delete this element")
    }

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(group.fields) { field in
                FieldRow(
                    label: field.label,
                    value: element.values[field.key] ?? "",
                    isSecret: field.type == .secret,
                    isRevealed: viewModel.isRevealed(elementID: element.id, fieldKey: field.key),
                    onReveal: { viewModel.toggleReveal(elementID: element.id, fieldKey: field.key) },
                    onCopy: {
                        viewModel.copy(
                            element.values[field.key] ?? "",
                            label: field.label,
                            concealed: field.type == .secret
                        )
                    }
                )
            }

            // note and last used are always present, not part of the schema. They go through
            // the same row container as the schema fields so their width can't drift from
            // them — previously they shrink-wrapped their text while the schema rows filled
            // the panel, which read as a layout bug.
            MetaRow(label: "note", value: element.note.isEmpty ? "—" : element.note, wraps: true)
            MetaRow(label: "last used", value: element.lastUsed, wraps: false)
        }
        .padding(.top, 17)
    }

    private var claimButtonLabel: String {
        guard let claim = element.claimedBy else { return "use + copy" }
        if viewModel.isMine(claim) { return "release" }
        // An offline holder's mark renders free: the button says so and claiming takes over.
        return viewModel.isEffectivelyFree(element)
            ? "use + copy (\(viewModel.memberName(claim.who)) offline)"
            : "in use by \(viewModel.memberName(claim.who))"
    }

    private var claimButtonStyle: (bg: Color, fg: Color, border: Color) {
        guard let claim = element.claimedBy else {
            return (NBColor.amber, NBColor.background, NBColor.amber)
        }
        if viewModel.isMine(claim) {
            return (.clear, NBColor.green, NBColor.green.opacity(0.4))
        }
        return (.clear, NBColor.textSecondary, NBColor.border)
    }

    private var actionsSection: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    viewModel.claimOrRelease(element.id)
                } label: {
                    Text(claimButtonLabel)
                        .font(NBFont.ui(11.5, weight: .bold))
                        .foregroundStyle(claimButtonStyle.fg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(claimButtonStyle.bg)
                        .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(claimButtonStyle.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
                }
                .buttonStyle(.nbPlain)

                if viewModel.loginUsername(for: element) != nil {
                    Button {
                        viewModel.loginOnSim(element)
                    } label: {
                        Text("⚡ login on sim")
                            .font(NBFont.ui(11))
                            .foregroundStyle(NBColor.textFieldValue)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(NBColor.border, lineWidth: 1))
                    }
                    .buttonStyle(.nbPlain)
                }
            }

            if viewModel.loginUsername(for: element) != nil {
                Text(viewModel.resolvedDeeplinkScheme.isEmpty
                     ? "no URL scheme yet — set one from the ▾ menu next to the collection name"
                     : "fires \(viewModel.resolvedDeeplinkScheme)://debug/login?user=…\(viewModel.loginPassword(for: element) != nil ? "&pass=…" : "")")
                    .font(NBFont.mono(10))
                    .foregroundStyle(NBColor.textMuted)
            }

            // Fallback for logins the deeplink can't drive (WebView/SSO like Okta): copy the
            // credentials and claim in one tap; release via the claim button above.
            if viewModel.isAuthElement(element) {
                Button {
                    viewModel.copyAuthAndClaim(element)
                } label: {
                    Text("⧉ copy login + password · mark in use")
                        .font(NBFont.ui(11))
                        .foregroundStyle(NBColor.amber)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(NBColor.amber.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.nbPlain)
                .padding(.top, 2)
            }

            // The escape hatch for a claim nobody can release. Without a backend the claimant
            // has no way to hand it back, so this is the only path off a locked row short of
            // deleting the element.
            if let claim = element.claimedBy, !viewModel.isMine(claim) {
                Button {
                    viewModel.takeOver(element.id)
                } label: {
                    Text("take over from \(viewModel.memberName(claim.who).lowercased())")
                        .font(NBFont.ui(11))
                        .foregroundStyle(NBColor.amber)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(NBColor.amber.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.nbPlain)
                .padding(.top, 2)
            }

            // Second entry point for notify-when-free (the row tooltip is the other) —
            // only meaningful when there are teammates who might free it.
            if let claim = element.claimedBy, !viewModel.isMine(claim), !viewModel.isSolo {
                Button {
                    viewModel.notifyWhenFree(element)
                } label: {
                    Text("🔔 notify me when it's free")
                        .font(NBFont.ui(11))
                        .foregroundStyle(NBColor.amber)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(NBColor.amber.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.nbPlain)
                .padding(.top, 2)
            }

        }
        .padding(.top, 18)
    }
}

/// A read-only label/value row (note, last used) matching the schema field rows' geometry.
private struct MetaRow: View {
    let label: String
    let value: String
    /// Notes can run to several lines; single-value rows stay on one.
    let wraps: Bool

    var body: some View {
        HStack(alignment: wraps ? .top : .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(NBFont.mono(10.5, weight: .medium))
                .foregroundStyle(NBColor.textMuted)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(NBFont.mono(10))
                .foregroundStyle(NBColor.textSecondaryAlt)
                .lineLimit(wraps ? nil : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(11)
        .background(NBColor.field)
        .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(NBColor.borderSubtle, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
        .frame(maxWidth: .infinity)
    }
}

private struct FieldRow: View {
    let label: String
    let value: String
    let isSecret: Bool
    let isRevealed: Bool
    let onReveal: () -> Void
    let onCopy: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(NBFont.mono(10.5, weight: .medium))
                .foregroundStyle(NBColor.textMuted)
                .frame(width: 72, alignment: .leading)
            Text(isSecret && !isRevealed ? "••••••••••" : value)
                .font(NBFont.mono(10.5))
                .foregroundStyle(NBColor.textFieldValue)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isSecret {
                Button(action: onReveal) {
                    Text(isRevealed ? "hide" : "reveal")
                        .font(NBFont.mono(10))
                        .foregroundStyle(NBColor.textDim)
                }
                .buttonStyle(.nbPlain)
            }
            Text("⧉")
                .font(NBFont.mono(10))
                .foregroundStyle(NBColor.amber)
        }
        .padding(11)
        .background(NBColor.field)
        .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(hovering ? NBColor.amber : NBColor.borderSubtle, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: onCopy)
        .onHover { hovering = $0 }
    }
}
