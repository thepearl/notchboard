# Notchboard

macOS utility that docks a shared, claimable catalogue of test accounts and fixtures to the iOS Simulator window, so mobile teams stop hunting for working logins in Slack.

Product source of truth is `vision.md`. Section 13 is a running implementation log ("what's real vs still vision") and must be updated whenever the build evolves. Currently the app is a local-only prototype: full docking + catalogue UI, no backend, no sync, mock seed data.

## Build and run

```bash
# Build (single scheme, single app target)
xcodebuild -project notchboard.xcodeproj -scheme notchboard -configuration Debug build

# Build without signing (for verification only)
xcodebuild -project notchboard.xcodeproj -scheme notchboard -configuration Debug build CODE_SIGNING_ALLOWED=NO

# Test (Swift Testing, hosted in the app target)
xcodebuild -project notchboard.xcodeproj -scheme notchboard -destination 'platform=macOS' test
```

Tests live in `notchboardTests/` and use Swift Testing (`import Testing`, `@Test`/`#expect`), never
XCTest. The target is hosted by the app (`TEST_HOST`), so `AppDelegate.applicationDidFinishLaunching`
detects the test environment and returns early — tests never start the panel, the timers, or the
monitors, and never read or write the user's real `state.json`. Keep that guard intact when touching
AppDelegate's startup, or a test run will start mutating real state.

CI (`.github/workflows/ci.yml`) runs build, test, and SwiftLint on push and PR. SwiftLint is
advisory (`--lenient`) until the existing warnings are burned down.

To exercise docking at runtime you need Simulator.app running and the Accessibility permission granted to the built app (System Settings → Privacy & Security → Accessibility). The app has no Dock icon. Its entry points are the menu-bar item and the panel itself.

## Hard constraints (do not change casually)

- `ENABLE_APP_SANDBOX = NO` in both configurations. A sandboxed process's Accessibility calls against other processes are silently swallowed. No permission dialog ever appears and there is no error. This cost real debugging time (vision.md §13.3). Never re-enable it.
- `FloatingPanel` is a borderless `.nonactivatingPanel` that overrides `canBecomeKey`. This is what lets text fields work without the app ever stealing focus from Simulator or Xcode. Changing the style mask or activation policy breaks the core UX.
- The app runs as an agent via `NSApp.setActivationPolicy(.accessory)` in `AppDelegate` (not `LSUIElement` in Info.plist — the Info.plist is generated, `GENERATE_INFOPLIST_FILE = YES`).
- Accessibility API coordinates are top-left origin relative to the primary screen (the one whose AppKit frame origin is zero). AppKit is bottom-left origin. The conversion lives in `Docking/SimulatorWindowTracker.swift`. AX reads run on a background task because they can block for seconds when Simulator is busy. NSScreen reads stay on the main thread.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is on. Everything is main-actor by default. Be explicit when moving work off the main actor.
- Deployment target macOS 26.3, Swift 5 mode, hardened runtime on, no entitlements file.
- **No continuous animation in the panel at rest.** The panel is a transparent window, so every animation frame makes the window server re-blend the whole 404×592 panel plus its 70pt shadow. One pulsing 6pt dot measured ~20% of a CPU core for as long as the panel was open, against ~0.1% with nothing animating (full numbers in vision.md §13.4). Gate any animation behind hover or another interaction, and animate opacity rather than shadow radii or blur. `IdleAnimationGuardTests` fails the build if a `repeatForever` appears without such a gate.
- **Global shortcuts go through Carbon `RegisterEventHotKey`, never an `NSEvent` global monitor.** A global `NSEvent` monitor observes but cannot consume a keystroke (its handler returns `Void`, deliberately, so a background app can't swallow another app's keys), which is why the earlier version double-triggered Xcode's New File on every ⌘N. `Shortcuts/GlobalHotKeys.swift` owns the Carbon path; this is the same mechanism soffes/HotKey, sindresorhus/KeyboardShortcuts, Maccy and Ice all use, and it needs no TCC permission of its own. Plain chords also work inside the panel via the local monitor, scoped to `event.window === panel`.
- **A claimed chord is consumed system-wide, so registration is deliberately scoped twice over:** only while the panel can respond, and only while Xcode, Simulator, or Notchboard itself is frontmost (`AppDelegate.hotKeyHostBundleIDs`). That scoping is what makes the default ⌃K/⌃N acceptable at all: ⌃K and ⌃N are real bindings elsewhere (Cocoa's `deleteToEndOfParagraph:`/`moveDown:` per `StandardKeyBinding.dict`, and zsh/bash `kill-line`/`down-line-or-history`), so Notchboard hands them back the moment you switch to Terminal. Do not widen that scope without re-reading vision.md §13.5.
- **`SimulatorWindowTracker`'s published properties are written through equality guards.** Observation notifies on every write, not every change, so an unguarded assignment in the ~3x/sec poll re-renders any observing SwiftUI view at poll rate. For the same reason, no view should take a SwiftUI dependency on the tracker; AppDelegate's reposition tick bridges tracker state into the view models instead.
- **A failed Keychain write must never be treated as stored.** `SecretsStore.save` returns `Bool` precisely so `AppStateStore` only swaps in the placeholder when the write landed — persisting a placeholder that points at nothing turns a transient locked keychain into permanent loss of the secret.

## Architecture

`notchboardApp.swift` is an empty shell (`Settings { EmptyView() }`). The real composition root is `AppDelegate.swift`, which owns:

- the `FloatingPanel` hosting all SwiftUI content via `NSHostingController`
- the menu-bar status item and the Settings window
- global ⌘K (open + focus search) and ⌘N (add element) via `NSEvent` monitors
- a 0.15s reposition timer that reads view-model state and the tracked Simulator frame, then sizes/positions the panel per `PanelContentMode` (onboarding / notch / notch+coach-mark / expanded panel). Mode transitions animate, position tracking snaps 1:1.

State lives in three `@Observable` classes, injected into views as `@Bindable`:

- `ViewModels/NotchboardViewModel.swift` — all catalogue state: workspace data, navigation, filters, forms, toasts, settings. Known god object, flagged for decomposition.
- `ViewModels/OnboardingViewModel.swift` — 4-step onboarding flow state.
- `Docking/SimulatorWindowTracker.swift` — polls the AX API ~3x/sec for Simulator's presence and window frame. Polling (not `AXObserver`) is a documented deliberate tradeoff.

Other modules:

- `Models/Models.swift` — Codable value types (`NBWorkspace` → `NBGroup` → `NBElement`, schema-driven `values: [String: String]`). `Models/MockData.swift` seeds first launch.
- `Persistence/AppStateStore.swift` — whole app state as one versioned JSON file at `~/Library/Application Support/Notchboard/state.json`, saved debounced from `NotchboardSceneView`'s `.onChange` handlers and flushed on quit. Secret-typed field values never enter the JSON: `SecretsStore` swaps them into the Keychain (service `flourix.notchboard.secrets`) on save and back on load. Delete the state file to simulate a first launch. A corrupt file is moved to `state.json.corrupt`, not discarded.
- `DesignSystem/` — `NBColor`, `NBFont`, `NBMetrics`. The visual direction ("dev-tool carbon", vision.md §7) is locked. Always use these constants, never raw hex or font literals in views.
- `Views/` — one folder per feature (Notch, Panel, List, Detail, Add, NewGroup, Onboarding, Settings, Toast).

## Conventions

- Type prefix `NB` for design-system and model types.
- Structs and enums for data, `@Observable` final classes only for the three state holders.
- Views stay dumb. Derived values and mutations belong in the view model (some views currently violate this, don't add more).
- Group business logic must key off group schema, not hardcoded group IDs like `"users"`/`"promos"` (existing violations in `secondaryText` and `DetailView` are known debt).
- Small files organised by feature. Match the existing comment style: file headers explain the why and link to vision.md sections.
- Commit format: `<type>: <description>` (feat, fix, refactor, docs, test, chore, perf, ci).

## Feature set (as of 2026-08-06)

Beyond the docking shell and catalogue, the following are implemented locally (no backend): full CRUD (edit/delete elements, edit/rename/delete groups with schema editing that preserves values via stable field ids, and a drag-to-reorder fields list), the `simctl` deeplink bridge ("login on sim" with a validated, configurable URL scheme in Settings) plus a copy-auth-and-claim fallback for SSO/WebView logins, a menu-bar fallback that shows the panel undocked when Simulator/Accessibility is unavailable, workspace export/import as JSON (secrets stripped), local notify-when-free notifications, keyboard navigation in the list, launch-at-login (with a requires-approval affordance), and a left/right dock-edge setting that mirrors the notch and coach-mark layout.

Secret values are the one thing never written to `state.json` or an export: they live in the Keychain. `NBGroup.secretFieldKeys` is the single definition of which fields are secret, and `NBWorkspace.mappingSecretValues` is the single traversal that pairs it with element values — export blanking, import blanking, and the placeholder swap all go through it. Changing a field away from the secret type drops its value and Keychain entry, blanking a secret deletes its entry, and orphaned entries are swept at launch.

One deliberate, documented exception to the secrets posture: `simctl` takes the deeplink URL as a command-line argument, so a password passed in the query is visible in the process list to other processes running as you while that short-lived process runs. There is no argv-free way to hand `simctl` a URL. See the header of `Docking/SimctlBridge.swift` — everything under the app's own control (its log lines, and `simctl`'s echoed stderr) is redacted.

## Known issues (post-audit 2026-08-06 — all 25 verified findings are fixed)

- `NotchboardViewModel` is a god object (chrome, data, navigation, forms, toasts, settings, ~850 lines). Decompose before backend work; the test target now makes that safe.
- No SwiftFormat config. SwiftLint config exists but runs advisory in CI, with warnings not yet burned down.
- Claim-age labels update on re-render (the 30s auto-release sweep triggers them), not on a per-minute tick of their own.
- `secondaryText` still special-cases `group.id == "promos"`/`"products"` for row subtitles (guarded on the fields existing). Known debt; the login button was made schema-driven.
- If `state.json` reaches a machine without the matching Keychain, secret fields load empty (no cross-machine secret sync by design in this local build). A Keychain *read error*, as opposed to a missing item, now keeps the placeholder rather than persisting an empty value.
- No presence and no real identity: claims are attributed to the literal string `"you"`, and the persisted onboarding name is not yet used as the claimant label. Both need the backend.
- Removing the model fields `onlineCount`, `liveSyncEnabled`, and the member avatar extras changed the persisted shape without bumping `schemaVersion`. Forward loading is fine (unknown keys are ignored), but a *older* build reading a new file will fail to decode it and move the file to `state.json.corrupt`. Only matters if you run an old build against new data.
