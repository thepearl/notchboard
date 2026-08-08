//
//  OnboardingView.swift
//  notchboard
//

import AppKit
import SwiftUI

struct OnboardingView: View {
    @Bindable var onboarding: OnboardingViewModel
    let onFinish: () -> Void
    let onToast: (String, NBToastColor) -> Void
    /// Applies the chosen starting point (step 3). Returns false if it couldn't, so the flow
    /// stays put rather than advancing into an empty app.
    let onChooseStartingPoint: (NBStartingPoint) -> Bool

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                titleBar

                VStack {
                    if onboarding.step > 1 {
                        HStack {
                            Button(action: onboarding.back) {
                                Text("← back")
                                    .font(NBFont.mono(10))
                                    .foregroundStyle(NBColor.textSecondary)
                            }
                            .buttonStyle(.nbPlain)
                            Spacer()
                        }
                        .padding(.bottom, 8)
                    }

                    stepContent
                        .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, 34)
                .padding(.top, 30)
                .padding(.bottom, 20)
                .frame(minHeight: 330)

                dots
                    .padding(.bottom, 16)
            }
            .frame(width: 468)
            .background(NBColor.panel)
            .overlay(RoundedRectangle(cornerRadius: NBMetrics.panelCornerRadius).stroke(NBColor.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: NBMetrics.panelCornerRadius))
            .shadow(color: .black.opacity(0.8), radius: 90, y: 40)
        }
    }

    /// Setup's own title bar. The three dots used to be pure decoration, which made them a
    /// trap — they look like the system's and people click them (team feedback: "all 3
    /// don't work"). Red now genuinely quits, and the other two are dimmed to half their
    /// former weight with tooltips saying why: there is no window to minimise or zoom
    /// during setup, and a button that lies is worse than one that's visibly unavailable.
    private var titleBar: some View {
        HStack(spacing: 7) {
            Button(action: quitFromSetup) {
                Circle()
                    .fill(NBColor.trafficRed)
                    .frame(width: 11, height: 11)
                    .contentShape(Circle())
            }
            .buttonStyle(.nbPlain)
            .help("quit notchboard")

            Circle().fill(NBColor.trafficAmber.opacity(0.3)).frame(width: 11, height: 11)
                .help("nothing to minimise during setup")
            Circle().fill(NBColor.trafficGreen.opacity(0.3)).frame(width: 11, height: 11)
                .help("setup is a fixed size")

            Spacer()
            Text("notchboard setup")
                .font(NBFont.mono(10))
                .foregroundStyle(NBColor.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(NBColor.titleBar)
        .overlay(alignment: .bottom) { Rectangle().fill(NBColor.headerBorder).frame(height: 1) }
    }

    private func quitFromSetup() {
        let alert = NSAlert()
        alert.messageText = "Quit notchboard?"
        alert.informativeText = "Setup isn't finished — nothing has been saved yet."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch onboarding.step {
        case 1: WelcomeStep(onNext: handleNext)
        case 2: IdentityStep(onboarding: onboarding, onNext: handleNext)
        case 3: StartingPointStep(
            onboarding: onboarding,
            onChoose: onChooseStartingPoint,
            onNext: handleNext
        )
        case 4: PermissionStep(onboarding: onboarding, onNext: handleNext)
        default: EmptyView()
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(1...4, id: \.self) { i in
                Circle()
                    .fill(onboarding.step >= i ? NBColor.amber : NBColor.border)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func handleNext() {
        switch onboarding.advance() {
        case .advanced:
            break
        case .finished:
            onFinish()
        case .error(let message):
            onToast(message, .red)
        }
    }
}

private struct WelcomeStep: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Rectangle().fill(NBColor.amber).frame(width: 22, height: 22)
            Text("notchboard")
                .font(NBFont.ui(23, weight: .bold))
                .foregroundStyle(NBColor.textPrimary)
                .tracking(-0.3)
                .padding(.top, 14)
            Text("shared test data, docked to your simulator")
                .font(NBFont.mono(10))
                .foregroundStyle(NBColor.textSecondaryAlt)
                .padding(.top, 5)
            Text("every test account, promo code and fixture you juggle, one tap from the simulator — works alone, built to be shared")
                .font(NBFont.ui(11.5))
                .foregroundStyle(NBColor.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 300)
                .padding(.top, 10)

            Button(action: onNext) {
                Text("get started →")
                    .font(NBFont.ui(11.5, weight: .bold))
                    .foregroundStyle(NBColor.background)
                    .padding(.horizontal, 24)
                    .frame(height: 36)
                    .background(NBColor.amber)
                    .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
            }
            .buttonStyle(.nbPlain)
            .padding(.top, 20)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct IdentityStep: View {
    @Bindable var onboarding: OnboardingViewModel
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("who are you?")
                .font(NBFont.ui(15, weight: .bold))
                .foregroundStyle(NBColor.textPrimary)
            Text("your name labels every element you mark in use — for you today, and for anyone you share your catalogue with later.")
                .font(NBFont.ui(11))
                .foregroundStyle(NBColor.textSecondary)
                .lineSpacing(3)
                .padding(.top, 4)

            Text("YOUR NAME")
                .nbMonoLabel(10.5, tracking: 0.8)
                .padding(.top, 16)

            TextField("", text: $onboarding.name, prompt: Text("e.g. John Doe").foregroundStyle(NBColor.textMuted))
                .textFieldStyle(.plain)
                .font(NBFont.ui(12))
                .foregroundStyle(NBColor.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(NBColor.field)
                .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(NBColor.borderSubtle, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
                .padding(.top, 5)

            HStack(spacing: 10) {
                Circle()
                    .fill(NBColor.green.opacity(0.12))
                    .overlay(Circle().stroke(NBColor.green.opacity(0.35), lineWidth: 1))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Text(onboarding.initials)
                            .font(NBFont.mono(10))
                            .foregroundStyle(NBColor.green)
                    )
                HStack(spacing: 0) {
                    Text("this is how you appear on elements you use · ").foregroundStyle(NBColor.textSecondary)
                    Text("● \(onboarding.firstNameLowercased)").foregroundStyle(NBColor.green)
                }
                .font(NBFont.mono(10))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(NBColor.field)
            .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(NBColor.borderSubtle, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
            .padding(.top, 14)

            Spacer()

            HStack {
                Spacer()
                Button(action: onNext) {
                    Text("continue →")
                        .font(NBFont.ui(11.5, weight: .bold))
                        .foregroundStyle(NBColor.background)
                        .padding(.horizontal, 24)
                        .frame(height: 36)
                        .background(NBColor.amber)
                        .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
                }
                .buttonStyle(.nbPlain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Step 3: pick what the first catalogue contains.
///
/// Replaces the old "join your team's workspace" step, which demanded an invite code before it
/// would let anyone through and then threw the code away — a hard team prerequisite for an app
/// that works perfectly well alone.
private struct StartingPointStep: View {
    @Bindable var onboarding: OnboardingViewModel
    /// Applies the chosen starting point. Returns false when it couldn't (import cancelled or
    /// the file was unreadable), in which case we stay on this step.
    let onChoose: (NBStartingPoint) -> Bool
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("start your catalogue")
                .font(NBFont.ui(15, weight: .bold))
                .foregroundStyle(NBColor.textPrimary)
            Text("it lives on this mac as one file. you can change all of this later.")
                .font(NBFont.ui(11))
                .foregroundStyle(NBColor.textSecondary)
                .padding(.top, 4)

            VStack(spacing: 6) {
                ForEach(NBStartingPoint.allCases) { option in
                    StartingPointCard(
                        option: option,
                        isSelected: onboarding.startingPoint == option
                    ) {
                        // Animated on the write, not with a blanket .animation on the
                        // container: the fields below slide out of the chosen card
                        // instead of appearing from nowhere mid-step.
                        withAnimation(.easeOut(duration: 0.2)) {
                            onboarding.startingPoint = option
                        }
                    }
                }
            }
            .padding(.top, 14)

            // Join-a-team's two inputs: the whole point of the invite redesign is that
            // this — one paste, one password — is a teammate's entire setup.
            if onboarding.startingPoint == .joinTeam {
                VStack(spacing: 5) {
                    joinField("", text: $onboarding.inviteText, prompt: "notchboard-room:…")
                    joinSecureField("", text: $onboarding.roomPassword, prompt: "room password (shared separately)")
                }
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()

            HStack {
                Spacer()

                Button {
                    if onChoose(onboarding.startingPoint) { onNext() }
                } label: {
                    Text(onboarding.startingPoint.ctaLabel)
                        .font(NBFont.ui(11.5, weight: .bold))
                        .foregroundStyle(NBColor.background)
                        .padding(.horizontal, 24)
                        .frame(height: 36)
                        .background(NBColor.amber)
                        .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
                }
                .buttonStyle(.nbPlain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Compact single-line field in the step's visual vocabulary (the identity step's
    /// field, shrunk to fit two of them under the option cards).
    private func joinField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        TextField(label, text: text, prompt: Text(prompt).foregroundStyle(NBColor.textMuted))
            .textFieldStyle(.plain)
            .font(NBFont.mono(11))
            .foregroundStyle(NBColor.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(NBColor.field)
            .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(NBColor.borderSubtle, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
    }

    private func joinSecureField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        SecureField(label, text: text, prompt: Text(prompt).foregroundStyle(NBColor.textMuted))
            .textFieldStyle(.plain)
            .font(NBFont.mono(11))
            .foregroundStyle(NBColor.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(NBColor.field)
            .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(NBColor.borderSubtle, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
    }
}

/// One selectable starting point. Geometry matches the permission step's card so the flow
/// keeps one visual vocabulary.
private struct StartingPointCard: View {
    let option: NBStartingPoint
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Text(option.glyph)
                .font(NBFont.mono(12))
                .foregroundStyle(isSelected ? NBColor.amber : NBColor.textSecondary)
                .frame(width: 26, height: 26)
                .background(isSelected ? NBColor.amber.opacity(0.1) : NBColor.chip)
                .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))

            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                    .font(NBFont.ui(12.5, weight: .semibold))
                    .foregroundStyle(NBColor.textPrimary)
                Text(option.detail)
                    .font(NBFont.mono(10))
                    .foregroundStyle(NBColor.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? NBColor.amber.opacity(0.05) : NBColor.field)
        .overlay(
            RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius)
                .stroke(isSelected ? NBColor.amber : NBColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

private struct AvatarBubble: View {
    let initials: String
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 20, height: 20)
            .overlay(Circle().stroke(NBColor.panel, lineWidth: 2))
            .overlay(Text(initials).font(NBFont.ui(8, weight: .bold)).foregroundStyle(.white))
    }
}

private struct PermissionStep: View {
    @Bindable var onboarding: OnboardingViewModel
    let onNext: () -> Void

    /// The system permission dialog is one-shot: once dismissed, repeated "grant access"
    /// clicks silently do nothing. After the first request the button becomes "open
    /// System Settings", which is the only actual way forward at that point.
    @State private var promptRequested = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("one permission, then we dock")
                .font(NBFont.ui(15, weight: .bold))
                .foregroundStyle(NBColor.textPrimary)
            Text("notchboard uses the macOS accessibility API to find your Simulator window and follow it. nothing is recorded or captured.")
                .font(NBFont.ui(11))
                .foregroundStyle(NBColor.textSecondary)
                .lineSpacing(3)
                .padding(.top, 4)

            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: NBMetrics.cardCornerRadius)
                    .fill(NBColor.border)
                    .frame(width: 28, height: 28)
                    .overlay(Text("⚙").font(.system(size: 13)).foregroundStyle(NBColor.textSecondaryAlt))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Accessibility — Notchboard.app")
                        .font(NBFont.ui(12, weight: .semibold))
                        .foregroundStyle(NBColor.textPrimaryAlt)
                    Text("System Settings → Privacy & Security")
                        .font(NBFont.mono(10))
                        .foregroundStyle(NBColor.textSecondary)
                }

                Spacer()

                if onboarding.accessibilityGranted {
                    Text("✓ granted")
                        .font(NBFont.mono(10))
                        .foregroundStyle(NBColor.green)
                } else {
                    Button {
                        if promptRequested {
                            AccessibilityPermission.openSystemSettings()
                        } else {
                            promptRequested = true
                            AccessibilityPermission.requestIfNeeded()
                        }
                    } label: {
                        Text(promptRequested ? "open System Settings" : "grant access")
                            .font(NBFont.mono(10))
                            .foregroundStyle(NBColor.amber)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(NBColor.amber.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(.nbPlain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(NBColor.field)
            .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(NBColor.borderSubtle, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
            .padding(.top, 16)
            .task {
                await onboarding.pollAccessibility()
            }

            Text(promptRequested && !onboarding.accessibilityGranted
                 ? "flip the Notchboard toggle on in the Accessibility list — this step updates by itself once you do."
                 : "same pattern RocketSim uses — a known, App-Store-approved approach.")
                .font(NBFont.mono(10))
                .foregroundStyle(NBColor.textMuted)
                .lineSpacing(4)
                .padding(.top, 10)

            Spacer()

            HStack {
                Spacer()
                Button(action: onNext) {
                    Text("finish & dock →")
                        .font(NBFont.ui(11.5, weight: .bold))
                        .foregroundStyle(onboarding.accessibilityGranted ? NBColor.background : NBColor.textSecondary)
                        .padding(.horizontal, 24)
                        .frame(height: 36)
                        .background(onboarding.accessibilityGranted ? NBColor.amber : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(onboarding.accessibilityGranted ? NBColor.amber : NBColor.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
                }
                .buttonStyle(.nbPlain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
