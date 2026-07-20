//
//  ExpandedPanelView.swift
//  notchboard
//

import SwiftUI

struct ExpandedPanelView: View {
    @Bindable var viewModel: NotchboardViewModel
    var searchFocus: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 0) {
            PanelHeaderView(
                workspaceName: viewModel.workspace.name,
                onlineCount: viewModel.workspace.onlineCount,
                onCollapse: viewModel.toggleExpanded
            )

            Group {
                switch viewModel.currentView {
                case .list:
                    ListView(viewModel: viewModel, searchFocus: searchFocus)
                case .detail(let elementID):
                    if let element = viewModel.selectedElement(id: elementID) {
                        DetailView(viewModel: viewModel, element: element)
                    } else {
                        ListView(viewModel: viewModel, searchFocus: searchFocus)
                    }
                case .add:
                    AddElementView(viewModel: viewModel)
                case .newGroup:
                    NewGroupView(viewModel: viewModel)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .frame(width: NBMetrics.panelWidth, height: NBMetrics.panelHeight)
        .background(NBColor.panel)
        .overlay(
            RoundedRectangle(cornerRadius: NBMetrics.panelCornerRadius)
                .stroke(NBColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: NBMetrics.panelCornerRadius))
        .shadow(color: .black.opacity(0.6), radius: 70, y: 30)
        .animation(.easeOut(duration: 0.2), value: isViewCase)
    }

    /// Cheap discriminator so `.animation(value:)` can compare view-case changes without
    /// requiring `NotchboardPanelView` associated values to be `Equatable`-friendly for SwiftUI diffing quirks.
    private var isViewCase: Int {
        switch viewModel.currentView {
        case .list: return 0
        case .detail: return 1
        case .add: return 2
        case .newGroup: return 3
        }
    }
}
