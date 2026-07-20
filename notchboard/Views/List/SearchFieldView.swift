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

            TextField("", text: $viewModel.searchText, prompt: Text("search name, tag, note…  ⌘K").foregroundStyle(NBColor.textMuted))
                .textFieldStyle(.plain)
                .font(NBFont.mono(10.5))
                .foregroundStyle(NBColor.textPrimaryAlt)
                .focused(isFocused)
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(NBColor.field)
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(isFocused.wrappedValue ? NBColor.amber : NBColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .onChange(of: viewModel.searchFocusToken) {
            isFocused.wrappedValue = true
        }
    }
}
