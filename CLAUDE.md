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
- Accessibility API coordinates are top-left origin. AppKit is bottom-left origin. The conversion lives in `Docking/SimulatorWindowTracker.swift` and currently assumes `NSScreen.screens.first` is the primary screen (a known multi-monitor limitation).
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
- `Persistence/AppStateStore.swift` — whole app state as one JSON file at `~/Library/Application Support/Notchboard/state.json`. Saved from `NotchboardSceneView`'s `.onChange` handlers. Delete that file to simulate a first launch.
- `DesignSystem/` — `NBColor`, `NBFont`, `NBMetrics`. The visual direction ("dev-tool carbon", vision.md §7) is locked. Always use these constants, never raw hex or font literals in views.
- `Views/` — one folder per feature (Notch, Panel, List, Detail, Add, NewGroup, Onboarding, Settings, Toast).

## Conventions

- Type prefix `NB` for design-system and model types.
- Structs and enums for data, `@Observable` final classes only for the three state holders.
- Views stay dumb. Derived values and mutations belong in the view model (some views currently violate this, don't add more).
- Group business logic must key off group schema, not hardcoded group IDs like `"users"`/`"promos"` (existing violations in `secondaryText` and `DetailView` are known debt).
- Small files organised by feature. Match the existing comment style: file headers explain the why and link to vision.md sections.
- Commit format: `<type>: <description>` (feat, fix, refactor, docs, test, chore, perf, ci).

## Known issues (audited 2026-07-20, fix before building on top)

- Crash risk: `NotchboardViewModel.activeGroup` force-unwraps and traps if persisted state has an empty or inconsistent `groups`/`groupOrder` (user-editable JSON reaches this path).
- Secret-typed field values persist in plaintext to `state.json` and are copied to the pasteboard without the concealed-type marker. Real fix is Keychain plus `org.nspasteboard.ConcealedType`.
- `PersistedAppState` has no schema version. Any model change silently resets user data to mock.
- Auto-release of claims is advertised in Settings but not implemented, and claim-age counters never tick.
- Every mutation re-encodes and rewrites the whole state file on the main thread with no debounce.
- Element IDs use millisecond timestamps (collision-prone). Use UUIDs.
- No `.gitignore`, no tests, no lint config, no CI.
