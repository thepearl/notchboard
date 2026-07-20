//
//  SettingsView.swift
//  notchboard
//
//  A normal (titled, resizable-off) window shown from the menu-bar status item — this is
//  Notchboard's only "regular" AppKit window, since everything else is the borderless
//  floating panel. Exposes the same configurable props the prototype modeled as props
//  (see vision.md §5.8).
//

import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: NotchboardViewModel
    let onReplayOnboarding: () -> Void

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Start expanded when docking", isOn: $viewModel.startExpanded)

                Stepper(value: $viewModel.autoReleaseMinutes, in: 5...240, step: 5) {
                    Text("Auto-release claims after \(viewModel.autoReleaseMinutes) min idle")
                }

                Toggle("Live sync (simulated presence)", isOn: $viewModel.liveSyncEnabled)
            }

            Section {
                TextField("Debug URL scheme", text: $viewModel.deeplinkScheme, prompt: Text("e.g. brewly"))
            } header: {
                Text("Simulator deeplink")
            } footer: {
                Text("“Login on sim” fires <scheme>://debug/login?user=<username> into the booted Simulator via xcrun simctl. Your app's debug build must register this URL scheme and handle that route.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Replay Onboarding…", action: onReplayOnboarding)
            } footer: {
                Text("Notchboard docks to the real iOS Simulator window via the macOS Accessibility API. It hides automatically when Simulator quits, is closed, or is minimized/hidden, and redocks the moment it's visible again.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 320)
    }
}

#Preview {
    SettingsView(viewModel: NotchboardViewModel(), onReplayOnboarding: {})
}
