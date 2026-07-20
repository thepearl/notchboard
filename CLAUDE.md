# Notchboard

macOS utility that docks a shared, claimable catalogue of test accounts and fixtures to the iOS Simulator window, so mobile teams stop hunting for working logins in Slack.

Product source of truth is `vision.md`. Section 13 is a running implementation log ("what's real vs still vision") and must be updated whenever the build evolves. Currently the app is a local-only prototype: full docking + catalogue UI, no backend, no sync, mock seed data.

## Build and run

```bash
# Build (single scheme, single app target)
xcodebuild -project notchboard.xcodeproj -scheme notchboard -configuration Debug build

# Build without signing (for verification only)
xcodebuild -project notchboard.xcodeproj -scheme notchboard -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

There is no test target yet. When one is added, use Swift Testing (`import Testing`, `@Test`/`#expect`), not XCTest.

To exercise docking at runtime you need Simulator.app running and the Accessibility permission granted to the built app (System Settings → Privacy & Security → Accessibility). The app has no Dock icon. Its entry points are the menu-bar item and the panel itself.

## Hard constraints (do not change casually)

- `ENABLE_APP_SANDBOX = NO` in both configurations. A sandboxed process's Accessibility calls against other processes are silently swallowed. No permission dialog ever appears and there is no error. This cost real debugging time (vision.md §13.3). Never re-enable it.
- `FloatingPanel` is a borderless `.nonactivatingPanel` that overrides `canBecomeKey`. This is what lets text fields work without the app ever stealing focus from Simulator or Xcode. Changing the style mask or activation policy breaks the core UX.
- The app runs as an agent via `NSApp.setActivationPolicy(.accessory)` in `AppDelegate` (not `LSUIElement` in Info.plist — the Info.plist is generated, `GENERATE_INFOPLIST_FILE = YES`).
- Accessibility API coordinates are top-left origin relative to the primary screen (the one whose AppKit frame origin is zero). AppKit is bottom-left origin. The conversion lives in `Docking/SimulatorWindowTracker.swift`. AX reads run on a background task because they can block for seconds when Simulator is busy. NSScreen reads stay on the main thread.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is on. Everything is main-actor by default. Be explicit when moving work off the main actor.
- Deployment target macOS 26.3, Swift 5 mode, hardened runtime on, no entitlements file.

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

## Known issues (audited 2026-07-20, critical and medium findings fixed the same day)

- `NotchboardViewModel` is a god object (chrome, data, navigation, forms, toasts, settings in one class). Decompose before backend work, ideally together with adding the test target.
- No test target, no SwiftLint/SwiftFormat config, no CI, no README.
- Claim-age labels update on re-render (the 30s auto-release sweep triggers them), not on a per-minute tick of their own.
- "Login on sim" and its caption are still gated on `group.id == "users"` (acceptable while it's a phase-3 stub).
- Dead code flagged by the audit: `replayOnboarding()`, `NBMetrics.simulatorWidth/Height`, the unused member-avatar model (`short`, `avatarColor`, `initials`).
- `print` → `os.Logger` migration done in Persistence; check any new code uses `Logger`.
