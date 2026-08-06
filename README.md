# Notchboard

A macOS utility that docks a shared, claimable catalogue of test accounts and fixtures to the
iOS Simulator window, so mobile teams stop hunting for working logins in Slack.

Notchboard runs as a menu-bar agent (no Dock icon). It finds the real Simulator window via the
Accessibility API and attaches a slim notch to its edge. Click the notch and the catalogue
opens next to the app you are testing: browse or search test accounts, see who has claimed
what, claim one yourself, and fire a debug deeplink straight into the booted simulator.

Product source of truth is [vision.md](vision.md). Section 13 is the running implementation log.

## Status

Local-only prototype. The full docking shell and catalogue work against on-disk data. There is
no backend, so nothing syncs between machines and other teammates' claims are seed data. Backend
and workspace sync are the next phase, deliberately not started.

## Requirements

- macOS 26.3 or later
- Xcode 26.6 or later
- Accessibility permission, granted to the built app in System Settings → Privacy & Security →
  Accessibility. Docking cannot work without it: reading another app's window frame is exactly
  what the permission gates.
- Simulator.app running, for the docked presentation. Without it the panel is still reachable
  undocked from the menu bar.

## Build and run

```bash
xcodebuild -project notchboard.xcodeproj -scheme notchboard -configuration Debug build
```

Verification build with no signing:

```bash
xcodebuild -project notchboard.xcodeproj -scheme notchboard -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Tests (Swift Testing, hosted in the app target):

```bash
xcodebuild -project notchboard.xcodeproj -scheme notchboard -destination 'platform=macOS' test
```

The app has no Dock icon. Its entry points are the menu-bar item and the panel itself.

## Using it

Onboarding runs on first launch: name, invite code (any code of six or more characters, since
there is no backend yet), then the Accessibility grant. After that the notch docks itself to
Simulator.

- Click the notch, or press ⌃K, to open the catalogue and focus search.
- ⌃N adds an element. Arrow keys move through the list, Return opens a row, Esc goes back.
- Claiming an element copies its primary field and marks it in use for the team. Claims
  auto-release after the idle window set in Settings.
- "Login on sim" fires `<scheme>://debug/login?user=…` into the booted simulator via
  `xcrun simctl openurl`. Set the scheme in Settings, and have your app's debug build register
  it and handle that route. For logins a deeplink cannot drive (SSO or WebView screens), use
  "copy login + password · mark in use" instead.
- The menu-bar item also exports and imports a workspace as JSON, replays onboarding, and shows
  the panel undocked when Simulator is not available.

The global chords are registered with Carbon's `RegisterEventHotKey`, so they are genuinely
consumed rather than merely observed. That means Notchboard owns the chord while it holds it,
so it only holds it while you are actually in the iOS-development context: the registration is
claimed when Xcode, Simulator or Notchboard is frontmost and the panel can respond, and handed
straight back otherwise. Switch to Terminal and ⌃K is `kill-line` again.

The modifier is a setting (Settings → Behavior → Global shortcut), because the choice is a real
tradeoff and only you know which you can spare:

| Modifier | What it costs |
| --- | --- |
| ⌃ Control (default) | ⌃K/⌃N are Cocoa text bindings (delete-to-end-of-paragraph, move-down) and shell bindings (kill-line, down-line-or-history) |
| ⌘ Command | ⌘N is New File in Xcode, ⌘K is Clear Console. Convenient to type, but it collides where you'd use it |
| ⌥⌘ Option-Command | Collides with essentially nothing, and matches what comparable menu-bar utilities ship |

Inside the panel, plain ⌘K and ⌘N always work regardless of that setting, since there is nothing
to collide with in Notchboard's own window.

## Where data lives

Workspace data and settings are one versioned JSON file:

```
~/Library/Application Support/Notchboard/state.json
```

Delete it to simulate a first launch. A file that cannot be decoded is moved aside to
`state.json.corrupt` rather than discarded.

Secret-typed field values never enter that file, or an export. They live in the login Keychain
under the service `flourix.notchboard.secrets`, keyed `<elementID>.<fieldKey>`. One consequence
worth knowing: carry a `state.json` to another machine without its Keychain and secret fields
load empty, by design in a build with no sync.

The deeplink is the one place a password leaves the Keychain in the clear: `simctl` takes the
URL as a command-line argument, so while that short-lived process runs the password is visible
to other processes running as you. There is no argv-free way to hand `simctl` a URL. These are
shared test credentials on a local dev tool, so the exposure is accepted and documented rather
than hidden — see the header of `Docking/SimctlBridge.swift`.

## Architecture

`AppDelegate` is the composition root: it owns the borderless non-activating panel, the
menu-bar item, the Settings window, the global shortcut monitors, and the timer that keeps the
panel docked to Simulator's live window frame.

State lives in three `@Observable` classes: `NotchboardViewModel` (catalogue, navigation,
forms, toasts, settings), `OnboardingViewModel` (the four-step flow), and
`SimulatorWindowTracker` (polls the Accessibility API for Simulator's window).

See [CLAUDE.md](CLAUDE.md) for the constraints that are load-bearing — the disabled App Sandbox,
the non-activating panel, the coordinate conversion, and the panel's animation budget — none of
which are safe to change casually.
