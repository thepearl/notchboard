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

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginNeedsApproval = LaunchAtLogin.status == .requiresApproval

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Start expanded when docking", isOn: $viewModel.startExpanded)

                Picker("Dock to", selection: $viewModel.dockEdge) {
                    ForEach(NBDockEdge.allCases) { edge in
                        Text(edge.label).tag(edge)
                    }
                }

                Stepper(value: $viewModel.autoReleaseMinutes, in: NotchboardViewModel.autoReleaseRange, step: 5) {
                    Text("Auto-release in-use elements after \(viewModel.autoReleaseMinutes) min idle")
                }

                Picker("Global shortcut", selection: $viewModel.hotKeyModifier) {
                    ForEach(NBHotKeyModifier.allCases) { modifier in
                        Text(modifier.label).tag(modifier)
                    }
                }
                Text(viewModel.hotKeyModifier.costNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        // Ignore our own write-backs, or reverting the toggle would fire a
                        // redundant unregister.
                        guard newValue != LaunchAtLogin.isEnabled else { return }
                        // Reflect what the system actually did — registration can fail
                        // (e.g. an unsigned build) or land in requires-approval, and the
                        // toggle shouldn't lie.
                        let status = LaunchAtLogin.setEnabled(newValue)
                        launchAtLoginNeedsApproval = status == .requiresApproval
                        launchAtLogin = status == .enabled
                    }

                if launchAtLoginNeedsApproval {
                    HStack {
                        Text("Pending your approval in Login Items")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items…") {
                            LaunchAtLogin.openSystemSettings()
                        }
                    }
                }
            }

            Section {
                TextField("Debug URL scheme", text: $viewModel.deeplinkScheme, prompt: Text("e.g. notchdemo"))
                    .onSubmit { viewModel.setDeeplinkScheme(viewModel.deeplinkScheme) }
                Toggle("Warn before mixing production with another environment", isOn: $viewModel.suppressProductionMixWarning.inverted)
            } header: {
                Text("Simulator deeplink — “\(viewModel.workspace.name)”")
            } footer: {
                Text("“Login on sim” fires <scheme>://debug/login?user=<username> into the booted Simulator via xcrun simctl. Your app's debug build must register this URL scheme and handle that route. Stored per collection: each catalogue describes one app, so switching collections switches the app you deeplink into.")
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

/// Lets a "suppress X" flag drive a "warn me about X" toggle without storing the same
/// answer twice — the stored form has to stay suppression-shaped because that is what
/// NSAlert's own "don't show again" checkbox produces.
private extension Binding where Value == Bool {
    var inverted: Binding<Bool> {
        Binding<Bool>(get: { !wrappedValue }, set: { wrappedValue = !$0 })
    }
}

#Preview {
    SettingsView(viewModel: NotchboardViewModel(), onReplayOnboarding: {})
}
