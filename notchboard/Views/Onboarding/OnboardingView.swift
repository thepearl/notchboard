//
//  OnboardingView.swift
//  notchboard
//

import SwiftUI

struct OnboardingView: View {
    @Bindable var onboarding: OnboardingViewModel
    let onFinish: () -> Void
    let onToast: (String, NBToastColor) -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                titleBar

                VStack {
                    if onboarding.step > 1 {
                        HStack {
                            Button(action: onboarding.back) {
                                Text("← back")
                                    .font(NBFont.mono(9))
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

    private var titleBar: some View {
        HStack(spacing: 7) {
            Circle().fill(NBColor.trafficRed).frame(width: 10, height: 10)
            Circle().fill(NBColor.trafficAmber).frame(width: 10, height: 10)
            Circle().fill(NBColor.trafficGreen).frame(width: 10, height: 10)
            Spacer()
            Text("notchboard setup")
                .font(NBFont.mono(9))
                .foregroundStyle(NBColor.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(NBColor.titleBar)
        .overlay(alignment: .bottom) { Rectangle().fill(NBColor.headerBorder).frame(height: 1) }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch onboarding.step {
        case 1: WelcomeStep(onNext: handleNext)
        case 2: IdentityStep(onboarding: onboarding, onNext: handleNext)
        case 3: JoinWorkspaceStep(onboarding: onboarding, onNext: handleNext, onCreateInstead: {
            onToast("create-workspace flow: phase 2 — use an invite code for now", .amber)
        })
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
            Text("one live catalogue of test accounts and fixtures for the whole team — no more “anyone got a working login?”")
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
            Text("your name shows on every element you claim, so teammates know who to ping.")
                .font(NBFont.ui(11))
                .foregroundStyle(NBColor.textSecondary)
                .lineSpacing(3)
                .padding(.top, 4)

            Text("YOUR NAME")
                .nbMonoLabel(8, tracking: 0.8)
                .padding(.top, 16)

            TextField("", text: $onboarding.name, prompt: Text("e.g. Nadia Benali").foregroundStyle(NBColor.textMuted))
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
                            .font(NBFont.mono(9))
                            .foregroundStyle(NBColor.green)
                    )
                HStack(spacing: 0) {
                    Text("this is how your claims appear · ").foregroundStyle(NBColor.textSecondary)
                    Text("● \(onboarding.firstNameLowercased)").foregroundStyle(NBColor.green)
                }
                .font(NBFont.mono(9))
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

private struct JoinWorkspaceStep: View {
    @Bindable var onboarding: OnboardingViewModel
    let onNext: () -> Void
    let onCreateInstead: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("join your team's workspace")
                .font(NBFont.ui(15, weight: .bold))
                .foregroundStyle(NBColor.textPrimary)
            Text("everyone in a workspace sees the same live data.")
                .font(NBFont.ui(11))
                .foregroundStyle(NBColor.textSecondary)
                .padding(.top, 4)

            Text("INVITE CODE")
                .nbMonoLabel(8, tracking: 0.8)
                .padding(.top, 14)

            TextField("", text: Binding(
                get: { onboarding.code },
                set: { onboarding.code = $0.uppercased() }
            ), prompt: Text("NB-XXXX-XXXX").foregroundStyle(NBColor.textMuted))
                .textFieldStyle(.plain)
                .font(NBFont.mono(11))
                .tracking(1)
                .foregroundStyle(NBColor.amber)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(NBColor.field)
                .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(NBColor.borderSubtle, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
                .padding(.top, 5)

            if onboarding.codeLooksValid {
                foundWorkspaceCard
                    .padding(.top, 12)
            }

            Spacer()

            HStack {
                Button(action: onCreateInstead) {
                    Text("create a new workspace instead")
                        .font(NBFont.mono(9))
                        .foregroundStyle(NBColor.textSecondary)
                }
                .buttonStyle(.nbPlain)

                Spacer()

                Button(action: onNext) {
                    Text(onboarding.codeLooksValid ? "join \(Self.joinedWorkspace.name) →" : "join →")
                        .font(NBFont.ui(11.5, weight: .bold))
                        .foregroundStyle(onboarding.codeLooksValid ? NBColor.background : NBColor.textSecondary)
                        .padding(.horizontal, 24)
                        .frame(height: 36)
                        .background(onboarding.codeLooksValid ? NBColor.amber : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(onboarding.codeLooksValid ? NBColor.amber : NBColor.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
                }
                .buttonStyle(.nbPlain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The workspace the mock invite code "finds" — the same seed data the app actually
    /// loads, so the numbers on this card are real rather than a hardcoded lie.
    private static let joinedWorkspace = MockData.workspace()

    private var foundWorkspaceCard: some View {
        let workspace = Self.joinedWorkspace
        return HStack(spacing: 11) {
            Rectangle()
                .fill(NBColor.amber)
                .frame(width: 26, height: 26)
                .overlay(Text("A").font(NBFont.ui(12, weight: .bold)).foregroundStyle(NBColor.background))

            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .font(NBFont.ui(12.5, weight: .bold))
                    .foregroundStyle(NBColor.textPrimary)
                Text("\(workspace.memberCount) members · \(workspace.groups.count) groups · \(workspace.elementCount) elements")
                    .font(NBFont.mono(8.5))
                    .foregroundStyle(NBColor.textSecondary)
            }

            Spacer()

            HStack(spacing: -6) {
                AvatarBubble(initials: "TV", color: NBColor.memberPurple)
                AvatarBubble(initials: "SK", color: NBColor.memberPink)
                AvatarBubble(initials: "MN", color: NBColor.memberTeal)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(NBColor.green.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius).stroke(NBColor.green.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: NBMetrics.rowCornerRadius))
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
            .overlay(Text(initials).font(NBFont.ui(7, weight: .bold)).foregroundStyle(.white))
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
                        .font(NBFont.mono(8.5))
                        .foregroundStyle(NBColor.textSecondary)
                }

                Spacer()

                if onboarding.accessibilityGranted {
                    Text("✓ granted")
                        .font(NBFont.mono(9))
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
                            .font(NBFont.mono(9))
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
                .font(NBFont.mono(9))
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
