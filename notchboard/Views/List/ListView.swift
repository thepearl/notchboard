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
            // The freshness word is honest: "local" only while there is no room. With one
            // configured it reports the room's actual state — the first team test read a
            // connected room labelled "local" as a bug, and they were right.
            HStack(spacing: 0) {
                Text("\(viewModel.claimedCount) in use").foregroundStyle(NBColor.green)
                Text(" · \(connectionWord.text)").foregroundStyle(connectionWord.color)
            }
            .font(NBFont.mono(11))

            Spacer()

            if let online = viewModel.onlineCount {
                Text("\(online) online")
                    .font(NBFont.mono(11))
                    .foregroundStyle(NBColor.green)
            } else {
                Text("＋ \(viewModel.hotKeyModifier.symbolPrefix)N · search \(viewModel.hotKeyModifier.symbolPrefix)K")
                    .font(NBFont.mono(11))
                    .foregroundStyle(NBColor.textMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var connectionWord: (text: String, color: Color) {
        switch viewModel.activeRoomState {
        case nil: return ("local", NBColor.textSecondary)
        case .connected: return ("live", NBColor.green)
        case .connecting: return ("connecting…", NBColor.amber)
        case .failed: return ("room unreachable", NBColor.red)
        case .disconnected: return ("room offline", NBColor.amber)
        }
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
