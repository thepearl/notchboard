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
                    onToast: { message, color in viewModel.toast(message, color: color) }
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
        .onChange(of: viewModel.workspace) { persist() }
        .onChange(of: viewModel.autoReleaseMinutes) { persist() }
        .onChange(of: viewModel.startExpanded) { persist() }
        .onChange(of: viewModel.liveSyncEnabled) { persist() }
        .onChange(of: onboarding.isPresented) { persist() }
        .onChange(of: onboarding.name) { persist() }
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

    private var collapsedContent: some View {
        HStack(alignment: .top, spacing: 16) {
            CollapsedNotchView(claimedCount: viewModel.claimedCount) {
                viewModel.toggleExpanded()
            }
            .frame(width: NBMetrics.notchWidth, height: NBMetrics.notchHeight, alignment: .top)

            if viewModel.showCoachMark {
                CoachMarkView(onDone: { viewModel.showCoachMark = false })
                    .padding(.top, 24)
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func finishOnboarding() {
        onboarding.isPresented = false
        viewModel.showCoachMark = tracker.isSimulatorRunning
        viewModel.isExpanded = false
        viewModel.toast("joined acme-mobile · 21 elements synced", color: .green)
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
