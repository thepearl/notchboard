//
//  SearchFieldView.swift
//  notchboard
//

import SwiftUI

struct SearchFieldView: View {
    @Bindable var viewModel: NotchboardViewModel
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("⌕")
                    .font(NBFont.mono(11))
                    .foregroundStyle(NBColor.textMuted)

                TextField(
                    "",
                    text: $viewModel.searchText,
                    // Show the chord the user actually configured, not a hardcoded ⌘K.
                    prompt: Text("search name, tag, note…  \(viewModel.hotKeyModifier.symbolPrefix)K")
                        .foregroundStyle(NBColor.textMuted)
                )
                    .textFieldStyle(.plain)
                    .font(NBFont.mono(10.5))
                    .foregroundStyle(NBColor.textPrimaryAlt)
                    .focused(isFocused)
            }
            .padding(.horizontal, 11)
            .frame(height: NBMetrics.controlHeight)
            .background(NBColor.field)
            .overlay(
                RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius)
                    .stroke(isFocused.wrappedValue ? NBColor.amber : NBColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))

            // The primary action lives up here beside the search, not in the footer —
            // first team test: "+ new user" at the bottom read as a stray label, and
            // "user" alone didn't say a new *entry* was being created. Exactly the
            // field's height (NBMetrics.controlHeight) — also literal feedback.
            Button(action: viewModel.openAdd) {
                Text(addButtonLabel)
                    .font(NBFont.ui(14, weight: .semibold))
                    .foregroundStyle(NBColor.background)
                    .padding(.horizontal, 10)
                    // The height belongs on the label, not the Button: an outer frame gave
                    // a 29pt pill floating in a 34pt slot, so the visible control and its
                    // hit area disagreed — the exact trap documented in ElementRowView.
                    .frame(height: NBMetrics.controlHeight)
                    .background(NBColor.amber)
                    .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.nbPlain)
            .fixedSize(horizontal: true, vertical: false)
            .help("add a new \(viewModel.activeGroup.singular) entry (\(viewModel.hotKeyModifier.symbolPrefix)N)")
        }

        .padding(.horizontal, 16)
        .padding(.top, 12)
        .onChange(of: viewModel.searchFocusToken) {
            isFocused.wrappedValue = true
        }
    }

    /// The button hugs its text, so a long group name ate the search field beside it
    /// ("＋ new fidelity card entry"). Past a short name the noun is dropped rather than
    /// the layout: "users" keeps "＋ new user entry", anything longer becomes generic.
    private var addButtonLabel: String {
        let singular = viewModel.activeGroup.singular
        return singular.count <= Self.maxSingularInLabel
            ? "＋ new \(singular) entry"
            : "＋ new entry"
    }

    private static let maxSingularInLabel = 8
}
