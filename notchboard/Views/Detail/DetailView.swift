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
            return ("● claimed by \(viewModel.memberName(claim.who).lowercased()) · \(claim.minutesAgo)m", NBColor.green)
        }
        return ("○ free", NBColor.textSecondary)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 9) {
            Button(action: viewModel.backToList) {
                Text("←")
                    .font(NBFont.ui(13))
                    .foregroundStyle(NBColor.textSecondary)
                    .padding(4)
            }
            .buttonStyle(.plain)

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
                    .buttonStyle(.plain)
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
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(element.env.color.opacity(0.35), lineWidth: 1))
        }
    }

    private var fieldsSection: some View {
        VStack(spacing: 7) {
            ForEach(group.fields) { field in
                FieldRow(
                    label: field.label,
                    value: element.values[field.key] ?? "",
                    isSecret: field.type == .secret,
                    isRevealed: viewModel.isRevealed(elementID: element.id, fieldKey: field.key),
                    onReveal: { viewModel.toggleReveal(elementID: element.id, fieldKey: field.key) },
                    onCopy: { viewModel.copy(element.values[field.key] ?? "", label: field.label) }
                )
            }

            // note (always present, not part of schema)
            HStack(alignment: .top, spacing: 8) {
                Text("note")
                    .font(NBFont.mono(8))
                    .foregroundStyle(NBColor.textMuted)
                    .frame(width: 66, alignment: .leading)
                Text(element.note.isEmpty ? "—" : element.note)
                    .font(NBFont.mono(10))
                    .foregroundStyle(NBColor.textSecondaryAlt)
                    .lineLimit(nil)
            }
            .padding(11)
            .background(NBColor.field)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(NBColor.borderSubtle, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 3))

            // last used
            HStack(spacing: 8) {
                Text("last used")
                    .font(NBFont.mono(8))
                    .foregroundStyle(NBColor.textMuted)
                    .frame(width: 66, alignment: .leading)
                Text(element.lastUsed)
                    .font(NBFont.mono(10))
                    .foregroundStyle(NBColor.textSecondaryAlt)
            }
            .padding(11)
            .background(NBColor.field)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(NBColor.borderSubtle, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
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
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(claimButtonStyle.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .buttonStyle(.plain)

                if group.id == "users" {
                    Button {
                        viewModel.toast("deeplink fired → simulator (phase 3 — not yet wired)", color: .amber)
                    } label: {
                        Text("⚡ login on sim")
                            .font(NBFont.ui(11))
                            .foregroundStyle(NBColor.textFieldValue)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(NBColor.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            if group.id == "users" {
                Text("fires brewly://debug/login deeplink · phase 3")
                    .font(NBFont.mono(8))
                    .foregroundStyle(NBColor.textMuted)
            }
        }
        .padding(.top, 18)
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
                .buttonStyle(.plain)
            }
            Text("⧉")
                .font(NBFont.mono(9))
                .foregroundStyle(NBColor.amber)
        }
        .padding(11)
        .background(NBColor.field)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(hovering ? NBColor.amber : NBColor.borderSubtle, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .contentShape(Rectangle())
        .onTapGesture(perform: onCopy)
        .onHover { hovering = $0 }
    }
}
