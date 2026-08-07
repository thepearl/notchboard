//
//  PanelHeaderView.swift
//  notchboard
//

import SwiftUI

struct PanelHeaderView: View {
    @Bindable var viewModel: NotchboardViewModel
    let onCollapse: () -> Void

    @State private var collapseHovering = false

    var body: some View {
        HStack(spacing: 9) {
            Rectangle()
                .fill(NBColor.amber)
                .frame(width: 8, height: 8)

            Text("notchboard")
                .font(NBFont.ui(13, weight: .bold))
                .foregroundStyle(NBColor.textPrimary)
                .tracking(-0.2)

            collectionSwitcher

            Spacer()

            // No member count here: the app is solo until sync exists (vision.md §14), and
            // "1 members" was a team costume on a single-user tool. Its width now hosts
            // the collection switcher.

            Button(action: onCollapse) {
                Text("«")
                    .font(NBFont.mono(10))
                    .foregroundStyle(collapseHovering ? NBColor.textPrimaryAlt : NBColor.textSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius)
                            .stroke(collapseHovering ? NBColor.borderStrong : NBColor.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.nbPlain)
            .onHover { collapseHovering = $0 }
            .help("collapse to notch")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(
            Rectangle()
                .fill(Color.clear)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(NBColor.headerBorder).frame(height: 1)
                }
        )
    }

    /// The Phase 2 collection switcher (vision.md §14): the workspace name became a menu.
    /// System Menu chrome is fine here — it renders as our styled label until opened, and a
    /// native menu beats rebuilding popover behaviour by hand for four actions.
    private var collectionSwitcher: some View {
        Menu {
            ForEach(viewModel.collections) { collection in
                Button {
                    viewModel.switchCollection(collection.id)
                } label: {
                    if collection.id == viewModel.activeCollectionID {
                        Label(collection.name, systemImage: "checkmark")
                    } else {
                        Text(collection.name)
                    }
                }
            }
            Divider()
            Button("new collection…") {
                if let name = CollectionDialogs.promptForName(
                    title: "New collection",
                    message: "A collection is one catalogue with its own groups and deeplink scheme."
                ) {
                    viewModel.createCollection(named: name)
                }
            }
            Button("rename…") {
                if let name = CollectionDialogs.promptForName(
                    title: "Rename collection",
                    message: "Renames “\(viewModel.workspace.name)”.",
                    initial: viewModel.workspace.name
                ) {
                    viewModel.renameActiveCollection(to: name)
                }
            }
            Button("duplicate") {
                viewModel.duplicateActiveCollection()
            }
            Divider()
            // The deeplink scheme is per collection, and Settings was too far from where
            // people actually notice it's missing (the detail view's login button).
            Button(viewModel.deeplinkScheme.isEmpty
                   ? "set deeplink scheme…"
                   : "deeplink scheme: \(viewModel.resolvedDeeplinkScheme)://…") {
                if let scheme = CollectionDialogs.promptForScheme(
                    collectionName: viewModel.workspace.name,
                    current: viewModel.deeplinkScheme
                ) {
                    viewModel.setDeeplinkScheme(scheme)
                }
            }
            Divider()
            Button("delete…") {
                if CollectionDialogs.confirmDelete(
                    name: viewModel.workspace.name,
                    elementCount: viewModel.workspace.elementCount
                ) {
                    viewModel.deleteActiveCollection()
                }
            }
            .disabled(viewModel.collections.count == 1)
        } label: {
            Text("/ \(viewModel.workspace.name) ▾")
                .font(NBFont.mono(9.5))
                .foregroundStyle(NBColor.textSecondary)
        }
        .menuStyle(.button)
        .buttonStyle(.nbPlain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("switch or manage collections")
    }
}

#Preview {
    PanelHeaderView(viewModel: NotchboardViewModel(), onCollapse: {})
        .background(NBColor.panel)
}
