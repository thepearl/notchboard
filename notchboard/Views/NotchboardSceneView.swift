//
//  NotchboardSceneView.swift
//  notchboard
//
//  Top-level content hosted inside the floating panel (see AppDelegate). The panel's own
//  window frame is what docks to the real Simulator.app window — this view just renders
//  whichever piece of UI is currently active (onboarding / collapsed notch / expanded panel)
//  at exactly that size, with a transparent surround so the desktop shows through everywhere
//  except the actual notch/panel/dialog shapes.
//

import SwiftUI

struct NotchboardSceneView: View {
    @Bindable var viewModel: NotchboardViewModel
    @Bindable var onboarding: OnboardingViewModel
    var tracker: SimulatorWindowTracker

    @FocusState private var searchFocused: Bool

    var body: some View {
        Group {
            if onboarding.isPresented {
                OnboardingView(
                    onboarding: onboarding,
                    onFinish: finishOnboarding,
                    onToast: { message, color in viewModel.toast(message, color: color) },
                    onChooseStartingPoint: applyStartingPoint
                )
                .transition(panelTransition)
            } else if viewModel.isExpanded {
                ExpandedPanelView(viewModel: viewModel, searchFocus: $searchFocused)
                    .transition(panelTransition)
            } else {
                collapsedContent
                    .transition(notchTransition)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: contentModeKey)
        // No system focus rings anywhere in the panel. Every control here draws its own
        // active/hover state, and AppKit's blue ring around a borderless transparent panel
        // read as a stray rectangle rather than an affordance. The Settings window is a
        // separate, ordinary window and keeps its native rings.
        .focusEffectDisabled()
        .overlay(alignment: .bottomTrailing) {
            ToastStackView(toasts: viewModel.toasts)
                .padding(14)
        }
        .onKeyPress(.escape) {
            guard !onboarding.isPresented else { return .ignored }
            if case .list = viewModel.currentView {
                return .ignored
            }
            viewModel.backToList()
            return .handled
        }
        // Collections cover the old per-workspace and per-scheme observations: the deeplink
        // scheme lives inside NBCollection now, so one Equatable comparison catches both
        // catalogue mutations and settings edits.
        .onChange(of: viewModel.collections) { persist() }
        .onChange(of: viewModel.activeCollectionID) { persist() }
        .onChange(of: viewModel.autoReleaseMinutes) { persist() }
        .onChange(of: viewModel.startExpanded) { persist() }
        .onChange(of: viewModel.dockEdge) { persist() }
        .onChange(of: viewModel.hotKeyModifier) { persist() }
        .onChange(of: viewModel.pendingCoachMark) { persist() }
        .onChange(of: onboarding.isPresented) { persist() }
        .onChange(of: onboarding.name) {
            // The onboarding name is the claim label (vision.md §14.2) — keep the view
            // model's copy in step so claims made right after typing it are labelled.
            viewModel.selfName = onboarding.name
            persist()
        }
        // Deliberately NOT observing the tracker here: its properties are rewritten by a
        // sub-second poll, and a SwiftUI dependency on it re-rendered the whole panel tree
        // several times per second (~25% CPU, caught by profiling). The deferred coach
        // mark is promoted by AppDelegate's reposition tick instead.
    }

    private func persist() {
        let state = viewModel.persistableState(
            onboardingCompleted: !onboarding.isPresented,
            onboardingName: onboarding.name
        )
        // Debounced — bursts of mutations coalesce into one write. AppDelegate flushes a
        // final immediate save on termination.
        AppStateStore.scheduleSave(state)
    }

    /// A cheap discriminator so `.animation(value:)` only fires a crossfade on genuine
    /// content-mode changes (onboarding ↔ notch ↔ panel), not on every unrelated state
    /// mutation inside whichever view is currently showing.
    private var contentModeKey: Int {
        if onboarding.isPresented { return 0 }
        return viewModel.isExpanded ? 1 : 2
    }

    private var panelTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .leading)),
            removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .leading))
        )
    }

    private var notchTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.9, anchor: .leading)),
            removal: .opacity.combined(with: .scale(scale: 0.94, anchor: .leading))
        )
    }

    /// Collapsed layout mirrors the dock edge: the notch sits on the side flush against
    /// the Simulator window (leading when docked right of it, trailing when docked left),
    /// with the coach mark on the outward side. Ignoring the edge left the notch floating
    /// the full coach-mark width away from Simulator whenever "Dock to: left" was set.
    private var collapsedContent: some View {
        HStack(alignment: .top, spacing: 16) {
            if viewModel.dockEdge == .right {
                notch
                coachMarkIfShown
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                coachMarkIfShown
                notch
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var notch: some View {
        CollapsedNotchView(claimedCount: viewModel.claimedCount, edge: viewModel.dockEdge) {
            viewModel.toggleExpanded()
        }
        .frame(width: NBMetrics.notchWidth, height: NBMetrics.notchHeight, alignment: .top)
    }

    @ViewBuilder
    private var coachMarkIfShown: some View {
        if viewModel.showCoachMark {
            CoachMarkView(onDone: { viewModel.showCoachMark = false })
                .padding(.top, 24)
        }
    }

    /// Fills the first catalogue from the starting point chosen in onboarding step 3.
    /// Returns false when the user cancels the file picker or the file won't parse, so the
    /// flow stays on step 3 instead of advancing into an app with nothing in it.
    private func applyStartingPoint(_ choice: NBStartingPoint) -> Bool {
        switch choice {
        case .sample:
            viewModel.adoptSeedWorkspace(MockData.workspace())
            return true
        case .empty:
            viewModel.adoptSeedWorkspace(MockData.emptyWorkspace())
            return true
        case .importFile:
            guard let url = WorkspaceFileDialogs.chooseImportFile() else { return false }
            do {
                // The interactive flow handles the encrypted-secrets prompt (with its
                // skip path); nil means the user cancelled there.
                guard let imported = try WorkspaceImportFlow.importInteractively(from: url) else { return false }
                viewModel.replaceActiveCollection(with: imported)
                return true
            } catch {
                viewModel.toast(WorkspaceImportFlow.userMessage(for: error), color: .red)
                return false
            }
        }
    }

    private func finishOnboarding() {
        onboarding.isPresented = false
        // Coach mark now if Simulator is visible, deferred to its first appearance if not —
        // never silently dropped.
        viewModel.showCoachMark = tracker.isSimulatorRunning
        viewModel.pendingCoachMark = !tracker.isSimulatorRunning
        viewModel.isExpanded = false
        // Speaks to what the user actually chose, with real numbers, and never claims to have
        // "joined" anything — there is nothing to join.
        switch onboarding.startingPoint {
        case .sample:
            viewModel.toast("loaded “\(viewModel.workspace.name)” · \(viewModel.workspace.elementCount) elements", color: .green)
        case .empty:
            viewModel.toast("“\(viewModel.workspace.name)” ready — \(viewModel.hotKeyModifier.symbolPrefix)N to add your first element", color: .green)
        case .importFile:
            break // replaceWorkspace already toasted what it imported
        }
    }
}

#Preview("Expanded panel") {
    let vm = NotchboardViewModel()
    let ob = OnboardingViewModel()
    ob.isPresented = false
    return NotchboardSceneView(viewModel: vm, onboarding: ob, tracker: SimulatorWindowTracker())
        .frame(width: NBMetrics.panelWidth, height: NBMetrics.panelHeight)
}

#Preview("Onboarding") {
    NotchboardSceneView(viewModel: NotchboardViewModel(), onboarding: OnboardingViewModel(), tracker: SimulatorWindowTracker())
        .frame(width: 468, height: 470)
}
