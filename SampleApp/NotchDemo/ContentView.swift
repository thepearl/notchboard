//
//  ContentView.swift
//  NotchDemo
//
//  A minimal login flow whose only job is to prove Notchboard's deeplink bridge end to
//  end: Notchboard runs `xcrun simctl openurl booted "notchdemo://debug/login?user=…&pass=…"`,
//  this app receives it in onOpenURL, fills the form, and signs in.
//
//  The integration a real app needs is exactly the ~20 lines in `handleDeeplink`.
//

import SwiftUI

struct ContentView: View {
    @State private var username = ""
    @State private var password = ""
    @State private var signedInUser: String?
    @State private var viaDeeplink = false
    @State private var lastError: String?

    var body: some View {
        Group {
            if let user = signedInUser {
                home(user: user)
            } else {
                loginForm
            }
        }
        // The Notchboard integration point. Everything else in this file is scenery.
        .onOpenURL(perform: handleDeeplink)
    }

    // MARK: - Deeplink handling

    /// Handles `notchdemo://debug/login?user=<username>&pass=<password>`.
    /// `pass` is optional — username-only catalogues still prefill the login.
    private func handleDeeplink(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "notchdemo",
              components.host == "debug",
              components.path == "/login",
              let user = components.queryItems?.first(where: { $0.name == "user" })?.value,
              !user.isEmpty else {
            lastError = "unhandled URL: \(url.absoluteString)"
            return
        }
        let pass = components.queryItems?.first(where: { $0.name == "pass" })?.value

        // Reset any existing session, fill the form visibly, then submit — the point of
        // the demo is *seeing* the flow a teammate would otherwise type by hand.
        signedInUser = nil
        lastError = nil
        username = user
        password = pass ?? ""
        signIn(viaDeeplink: true)
    }

    private func signIn(viaDeeplink: Bool = false) {
        guard !username.isEmpty else { return }
        self.viaDeeplink = viaDeeplink
        withAnimation(.easeInOut(duration: 0.25)) {
            signedInUser = username
        }
    }

    private func signOut() {
        withAnimation(.easeInOut(duration: 0.2)) {
            signedInUser = nil
            username = ""
            password = ""
            viaDeeplink = false
        }
    }

    // MARK: - Screens

    private var loginForm: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("brewly")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("demo target for the notchboard deeplink")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                TextField("email or username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("login-username")

                SecureField("password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("login-password")

                Button {
                    signIn()
                } label: {
                    Text("sign in")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .accessibilityIdentifier("login-submit")
            }
            .padding(.horizontal, 32)
            .padding(.top, 12)

            if let lastError {
                Text(lastError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 32)
            }

            Spacer()
            Text("notchdemo://debug/login?user=…&pass=…")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .padding(.bottom, 12)
        }
    }

    private func home(user: String) -> some View {
        VStack(spacing: 14) {
            Spacer()

            Circle()
                .fill(.orange.gradient)
                .frame(width: 74, height: 74)
                .overlay(
                    Text(String(user.prefix(2)).uppercased())
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                )

            Text("signed in")
                .font(.title2.bold())
            Text(user)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("home-user")

            if viaDeeplink {
                Label("logged in via notchboard deeplink", systemImage: "bolt.fill")
                    .font(.footnote.bold())
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.orange.opacity(0.12), in: Capsule())
                    .accessibilityIdentifier("deeplink-badge")
            }

            Spacer()

            Button("sign out", action: signOut)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
        }
    }
}

#Preview {
    ContentView()
}
