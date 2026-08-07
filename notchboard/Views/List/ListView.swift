//
//  ListView.swift
//  notchboard
//

import SwiftUI

struct ListView: View {
    @Bindable var viewModel: NotchboardViewModel
    var searchFocus: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 0) {
            EnvironmentFilterView(viewModel: viewModel)
            SearchFieldView(viewModel: viewModel, isFocused: searchFocus)
            GroupTabsView(viewModel: viewModel)

            // Rows container
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(viewModel.filteredElements) { element in
                            ElementRowView(
                                viewModel: viewModel,
                                element: element,
                                isKeyboardSelected: viewModel.keyboardSelectionID == element.id
                            )
                            .id(element.id)
                        }
                        if viewModel.filteredElements.isEmpty {
                            RowsEmptyStateView()
                        }
                    }
                    .padding(6)
                }
                .onChange(of: viewModel.keyboardSelectionID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .background(NBColor.field)
            .overlay(
                RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius)
                    .stroke(NBColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ListFooterView(viewModel: viewModel)
        }
        // Focusable so the arrow keys and Return reach `onKeyPress`, but without the system
        // focus ring: this view wraps the entire list, so AppKit drew a blue rounded rectangle
        // around the whole panel body the moment anything inside it was clicked — including
        // the env chips. The keyboard-selected row has its own amber outline, which is the
        // focus affordance this design wants.
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { viewModel.moveKeyboardSelection(1); return .handled }
        .onKeyPress(.upArrow) { viewModel.moveKeyboardSelection(-1); return .handled }
        .onKeyPress(.return) { viewModel.openKeyboardSelection() ? .handled : .ignored }
    }
}

private struct ListFooterView: View {
    @Bindable var viewModel: NotchboardViewModel

    var body: some View {
        HStack {
            // No fake "sync Ns ago" freshness — there is no sync in this local build.
            HStack(spacing: 0) {
                Text("\(viewModel.claimedCount) in use").foregroundStyle(NBColor.green)
                Text(" · local").foregroundStyle(NBColor.textSecondary)
            }
            .font(NBFont.mono(9.5))

            Spacer()

            Button(action: viewModel.openAdd) {
                Text("＋ new \(viewModel.activeGroup.singular) \(viewModel.hotKeyModifier.symbolPrefix)N")
                    .font(NBFont.mono(9.5))
                    .foregroundStyle(NBColor.amber)
            }
            .buttonStyle(.nbPlain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    struct PreviewHost: View {
        @FocusState var focused: Bool
        var body: some View {
            ListView(viewModel: NotchboardViewModel(), searchFocus: $focused)
                .frame(width: NBMetrics.panelWidth, height: NBMetrics.panelHeight - 60)
                .background(NBColor.panel)
        }
    }
    return PreviewHost()
}
