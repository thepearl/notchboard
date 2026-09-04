//
//  UpdatesSectionView.swift
//  notchboard
//
//  The Updates section of Settings (vision.md §13.20). Status is inline text: a toast posted from
//  this window would render in the panel, where nobody is looking. Stock Form styling like the
//  rest of the window, which is also why Sparkle's own dialog fits when it opens from here.
//

import SwiftUI

struct UpdatesSectionView: View {
    let updates: UpdateCenter

    var body: some View {
        Section {
            LabeledContent("Installed", value: updates.installedVersion)
            if updates.isSelfBuilt {
                Text(updates.statusText())
                    .foregroundStyle(.secondary)
            } else {
                // Ticks once a minute, only while this window is open, so "checked 3 h ago"
                // never goes stale. Settings is an opaque window: the panel's animation
                // budget (vision.md §13.4) does not apply here.
                TimelineView(.everyMinute) { context in
                    LabeledContent("Status", value: updates.statusText(now: context.date))
                }
                Toggle(isOn: automaticChecks) {
                    Text("Check for updates automatically")
                    Text("Once a day. You choose when to install.")
                }
                Button(updates.actionTitle) { updates.checkForUpdates() }
                    .disabled(!updates.canCheck)
            }
        } header: {
            Text("Updates")
        } footer: {
            if !updates.isSelfBuilt {
                Text("Updating keeps your Accessibility permission.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Reads Sparkle's value through the centre's mirror and writes through to Sparkle; the
    /// toggle flips when Sparkle confirms, never before.
    private var automaticChecks: Binding<Bool> {
        Binding(
            get: { updates.automaticallyChecks },
            set: { updates.setAutomaticallyChecks($0) }
        )
    }
}
