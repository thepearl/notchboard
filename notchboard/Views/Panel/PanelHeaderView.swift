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
            // The brand square doubles as the room connection dot (NBColor.syncState):
            // amber = local/connecting as it always was, green = room live, red = failed.
            Rectangle()
                .fill(NBColor.syncState(viewModel.activeRoomState))
                .frame(width: 8, height: 8)
                .help(connectionHelp)

            Text("notchboard")
                .font(NBFont.ui(13, weight: .bold))
                .foregroundStyle(NBColor.textPrimary)
                .tracking(-0.2)

            collectionSwitcher

            if let session = viewModel.activeRoomSession, session.state == .connected {
                Text("· \(session.onlineMemberIDs.count + 1) online")
                    .font(NBFont.mono(12))
                    .foregroundStyle(NBColor.green)
                    .help("people in this collection's room right now, including you")
            }

            Spacer()

            // No member count here: the app is solo until sync exists (vision.md §14), and
            // "1 members" was a team costume on a single-user tool. Its width now hosts
            // the collection switcher.

            // Sized like a control, not a glyph: at 10pt in a 5x1 pad this was the panel's
            // smallest target and nobody read it as "collapse" (team feedback).
            Button(action: onCollapse) {
                Image(systemName: "chevron.left.2")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(collapseHovering ? NBColor.textPrimaryAlt : NBColor.textSecondary)
                    .frame(width: 32, height: 26)
                    .background(collapseHovering ? NBColor.rowHover : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius)
                            .stroke(collapseHovering ? NBColor.borderStrong : NBColor.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.nbPlain)
            .onHover { collapseHovering = $0 }
            .help("collapse to the notch")
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
            Button("new collection") {
                if let name = CollectionDialogs.promptForName(
                    title: "New collection",
                    message: "A collection is one catalogue with its own groups and deeplink scheme."
                ) {
                    viewModel.createCollection(named: name)
                }
            }
            Button("rename") {
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
                   ? "set deeplink scheme"
                   : "deeplink scheme: \(viewModel.resolvedDeeplinkScheme)://…") {
                if let scheme = CollectionDialogs.promptForScheme(
                    collectionName: viewModel.workspace.name,
                    current: viewModel.deeplinkScheme
                ) {
                    viewModel.setDeeplinkScheme(scheme)
                }
            }
            // The team room lives beside the deeplink scheme: both are per-collection
            // wiring, discovered at the moment someone needs them (vision.md §14.3).
            Button(roomMenuTitle) {
                viewModel.setUpRoomFromMenu()
            }
            if viewModel.activeCollection.room != nil {
                // The invitation is one paste-able line (vision.md §14.3, revised
                // 2026-08-08) — the file export is a backup, not the invite.
                Button("copy room invite") {
                    viewModel.copyRoomInvite()
                }
                Button("leave room") {
                    viewModel.leaveRoomFromMenu()
                }
            } else {
                Button("join with an invite") {
                    viewModel.joinWithInviteFromMenu()
                }
            }
            Divider()
            Button("delete") {
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
                .font(NBFont.mono(12))
                .foregroundStyle(NBColor.textSecondary)
        }
        .menuStyle(.button)
        .buttonStyle(.nbPlain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("switch or manage collections")
    }

    private var roomMenuTitle: String {
        guard let room = viewModel.activeCollection.room else { return "set up team room" }
        switch viewModel.activeRoomState {
        case .connected: return "room: \(room.room) · connected"
        case .connecting: return "room: \(room.room) · connecting…"
        case .failed: return "room: \(room.room) · unreachable — fix"
        default: return "room: \(room.room) · join"
        }
    }

    private var connectionHelp: String {
        guard let room = viewModel.activeCollection.room else { return "local collection — no team room" }
        switch viewModel.activeRoomState {
        case .connected: return "room “\(room.room)” connected"
        case .connecting: return "connecting to “\(room.room)”…"
        case .failed(let message): return "room “\(room.room)”: \(message)"
        default: return "room “\(room.room)” — not connected"
        }
    }
}

#Preview {
    PanelHeaderView(viewModel: NotchboardViewModel(), onCollapse: {})
        .background(NBColor.panel)
}
