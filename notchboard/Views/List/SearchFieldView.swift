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
        .frame(height: 34)
        .background(NBColor.field)
        .overlay(
            RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius)
                .stroke(isFocused.wrappedValue ? NBColor.amber : NBColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .onChange(of: viewModel.searchFocusToken) {
            isFocused.wrappedValue = true
        }
    }
}
