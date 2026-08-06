//
//  DetailView.swift
//  notchboard
//

import SwiftUI

struct DetailView: View {
    @Bindable var viewModel: NotchboardViewModel
    let element: NBElement

    @State private var confirmingDelete = false

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
            return ("● claimed by \(viewModel.memberName(claim.who).lowercased()) · \(claim.ageLabel)", NBColor.green)
        }
        return ("○ free", NBColor.textSecondary)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 9) {
            NBBackButton(action: viewModel.backToList)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(element.name)
                        .font(NBFont.ui(14, weight: .bold))
                        .foregroundStyle(NBColor.textPrimary)
                    Button {
                        viewModel.toggleFavorite(element.id)
                    } label: {
                        Text(element.isFavorite ? "★" : "☆")
                            .font(NBFont.ui(11))
                            .foregroundStyle(element.isFavorite ? NBColor.amber : NBColor.textMuted)
                    }
                    .buttonStyle(.nbPlain)
                }
                Text(claimLine.text)
                    .font(NBFont.mono(9))
                    .foregroundStyle(claimLine.color)
            }

            Spacer()

            Text(element.env.rawValue)
                .font(NBFont.mono(8.5))
                .foregroundStyle(element.env.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(element.env.color.opacity(0.35), lineWidth: 1))
        }
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
        guard let claim = element.claimedBy else { return "claim + copy" }
        return claim.who == "you" ? "release" : "claimed by \(viewModel.memberName(claim.who))"
    }

    private var claimButtonStyle: (bg: Color, fg: Color, border: Color) {
        guard let claim = element.claimedBy else {
            return (NBColor.amber, NBColor.background, NBColor.amber)
        }
        if claim.who == "you" {
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
                     ? "set a URL scheme in settings to enable deeplinks"
                     : "fires \(viewModel.resolvedDeeplinkScheme)://debug/login?user=…\(viewModel.loginPassword(for: element) != nil ? "&pass=…" : "")")
                    .font(NBFont.mono(8))
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

            // Second entry point for notify-when-free (the row tooltip is the other) —
            // useful exactly when someone opened the detail hoping to use the element.
            if let claim = element.claimedBy, claim.who != "you" {
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

            HStack(spacing: 10) {
                Button {
                    viewModel.openEdit(element)
                } label: {
                    Text("edit")
                        .font(NBFont.mono(9))
                        .foregroundStyle(NBColor.textSecondary)
                }
                .buttonStyle(.nbPlain)
                .nbHoverColor(NBColor.amber, base: NBColor.textSecondary)

                Button {
                    if confirmingDelete {
                        viewModel.deleteElement(element.id)
                    } else {
                        confirmingDelete = true
                    }
                } label: {
                    Text(confirmingDelete ? "really delete?" : "delete…")
                        .font(NBFont.mono(9))
                        .foregroundStyle(NBColor.red.opacity(confirmingDelete ? 1 : 0.7))
                }
                .buttonStyle(.nbPlain)
            }
            .padding(.top, 8)
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
                .font(NBFont.mono(8))
                .foregroundStyle(NBColor.textMuted)
                .frame(width: 66, alignment: .leading)
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
                .font(NBFont.mono(8))
                .foregroundStyle(NBColor.textMuted)
                .frame(width: 66, alignment: .leading)
            Text(isSecret && !isRevealed ? "••••••••••" : value)
                .font(NBFont.mono(10.5))
                .foregroundStyle(NBColor.textFieldValue)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isSecret {
                Button(action: onReveal) {
                    Text(isRevealed ? "hide" : "reveal")
                        .font(NBFont.mono(9))
                        .foregroundStyle(NBColor.textDim)
                }
                .buttonStyle(.nbPlain)
            }
            Text("⧉")
                .font(NBFont.mono(9))
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
