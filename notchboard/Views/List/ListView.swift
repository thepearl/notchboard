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
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.filteredElements) { element in
                        ElementRowView(viewModel: viewModel, element: element)
                    }
                    if viewModel.filteredElements.isEmpty {
                        RowsEmptyStateView()
                    }
                }
                .padding(6)
            }
            .background(NBColor.field)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(NBColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ListFooterView(viewModel: viewModel)
        }
    }
}

private struct ListFooterView: View {
    @Bindable var viewModel: NotchboardViewModel

    var body: some View {
        HStack {
            HStack(spacing: 0) {
                Text("\(viewModel.claimedCount) claimed").foregroundStyle(NBColor.green)
                Text(" · sync 0.4s ago").foregroundStyle(NBColor.textSecondary)
            }
            .font(NBFont.mono(9.5))

            Spacer()

            Button(action: viewModel.openAdd) {
                Text("＋ new \(viewModel.activeGroup.singular) ⌘N")
                    .font(NBFont.mono(9.5))
                    .foregroundStyle(NBColor.amber)
            }
            .buttonStyle(.plain)
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
