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

State lives in `@Observable` classes, injected into views as `@Bindable`. `NotchboardViewModel` was decomposed on 2026-08-07 (1228 → 886 lines) into a coordinator that owns its collaborators:

- `ViewModels/NotchboardViewModel.swift` — the coordinator: chrome, navigation, filters, settings, identity, and the actions needing several collaborators (claims, the deeplink bridge, import/export UX). Keeps `workspace`/`collections`/`deeplinkScheme`/`toasts` as facades over the store so read-modify-write call sites read as they always have.
- `ViewModels/CollectionStore.swift` — the data layer: every collection, the active one, element addressing (including the fully-addressed `mutate(_:group:collection:)` that async completions must use), collection lifecycle, group/element mutation, and the Keychain lifecycle that goes with deletion. **Nothing here toasts or navigates** — methods return what happened and the view model decides what to say. That is deliberate: this is what the sync milestone drives when a room message arrives from another Mac (vision.md §14).
- `ViewModels/ElementFormModel.swift` / `GroupFormModel.swift` — the two forms' drafts and the rules about typing (environment toggling, production-mix detection, validation, field-key derivation). Saving stays in the view model since it needs the catalogue and the toast stack. `AddElementView`/`NewGroupView` bind to these directly as `draft`.
- `ViewModels/ToastCenter.swift` — the message stack, with per-toast expiry.
- `Persistence/Clipboard.swift` — pasteboard writes and concealed-copy expiry.
- `Models/NBDeeplinkScheme.swift` — pure scheme normalisation, validation and URL building (the security boundary for the one feature that puts credentials in a URL).
- `ViewModels/OnboardingViewModel.swift` — 4-step onboarding flow state.
- `Docking/SimulatorWindowTracker.swift` — polls the AX API ~3x/sec for Simulator's presence and window frame. Polling (not `AXObserver`) is a documented deliberate tradeoff.

Other modules:

- `Models/Models.swift` — Codable value types (`NBWorkspace` → `NBGroup` → `NBElement`, schema-driven `values: [String: String]`). An element carries `environments: Set<NBEnvironment>`, not one value: the same credentials usually exist in dev *and* staging, and forcing a single choice made people duplicate rows. `.all` is a filter sentinel and never assignable. `Models/NBFieldValidation.swift` makes the field types real (number/url/date/bool/picker are validated at save; the form renders a matching control) — validation lives in the model because values also arrive from imports and hand-edited files. `Models/NBCollection.swift` wraps a workspace with its local-only id and per-collection deeplink scheme (the app holds several, Postman-style). `Models/MockData.swift` seeds first launch.
- `Persistence/AppStateStore.swift` — whole app state as one JSON file at `~/Library/Application Support/Notchboard/state.json` (shape: `collections` + `activeCollectionID` + `memberID`; no migrations pre-release — any other shape takes the corrupt-backup reset path, by design). Saved debounced from `NotchboardSceneView`'s `.onChange` handlers and flushed on quit. Secret-typed field values never enter the JSON: `SecretsStore` swaps them into the Keychain (service `flourix.notchboard.secrets`) on save and back on load. Delete the state file to simulate a first launch. A corrupt file is moved to `state.json.corrupt`, not discarded. Successful saves also feed `SnapshotStore`: periodic encrypted snapshots of all collections in `~/.notchboard/snapshots/`, sealed under a device-local Keychain key (service `flourix.notchboard.device` — deliberately out of pruneOrphans' reach), restorable from the menu bar.
- `DesignSystem/` — `NBColor`, `NBFont`, `NBMetrics`. The visual direction ("dev-tool carbon", vision.md §7) is locked. Always use these constants, never raw hex or font literals in views. The grey scale was lifted on 2026-08-07 for legibility (the prototype's `textSecondary`/`textMuted` sat near 2.5:1 against the panel; every step now clears 4.5:1) and the default mono label is 9.5pt, not 8pt. Don't reintroduce the old values — they were measured, not guessed.
- `Views/` — one folder per feature (Notch, Panel, List, Detail, Add, NewGroup, Onboarding, Settings, Toast).

## Conventions

- Type prefix `NB` for design-system and model types.
- Structs and enums for data, `@Observable` final classes only for the three state holders.
- Views stay dumb. Derived values and mutations belong in the view model (some views currently violate this, don't add more).
- Group business logic must key off group schema, not hardcoded group IDs like `"users"`/`"promos"` (existing violations in `secondaryText` and `DetailView` are known debt).
- Small files organised by feature. Match the existing comment style: file headers explain the why and link to vision.md sections.
- Commit format: `<type>: <description>` (feat, fix, refactor, docs, test, chore, perf, ci).
- **No compatibility code before first release** (decision 2026-08-07, vision.md §14.5). The app is unpublished with exactly one user, so migration shims are dead code by definition. Schema and format changes reset (`state.json`'s corrupt-backup path) or refuse (exact format-version match on imports), never migrate. Version stamps stay in the files so real migration history can begin at 1.0.
- **"claim" never appears in user-facing copy** (same decision set). The UI says "in use", "used by", "use + copy". Internal identifiers (`claimedBy`, `claimOrRelease`, …) keep their names — only labels, toasts, tooltips, notifications and settings copy follow the rule.

## Feature set (as of 2026-08-07)

Beyond the docking shell and catalogue, the following are implemented locally (no backend): full CRUD (edit/delete elements, edit/rename/delete groups with schema editing that preserves values via stable field ids, and a drag-to-reorder fields list), the `simctl` deeplink bridge ("login on sim" with a validated URL scheme, stored **per collection** and edited in Settings) plus a copy-auth-and-claim fallback for SSO/WebView logins, a menu-bar fallback that shows the panel undocked when Simulator/Accessibility is unavailable, local notify-when-free notifications, keyboard navigation in the list, launch-at-login (with a requires-approval affordance), and a left/right dock-edge setting that mirrors the notch and coach-mark layout.

Phase 2/3 of the collections plan landed 2026-08-07 (vision.md §13.8, constitution in §14): **multiple collections** with a header switcher (switch/new/rename/duplicate/delete), import that **adds** a collection instead of destroying, **local identity** (a persisted `memberID` plus the onboarding name as the in-use label), **encrypted exports** (a mandatory export password seals all secret values into an AES-GCM envelope via PBKDF2→HKDF; claims are stripped), a **passphrase generator** on the export prompt, **encrypted snapshots** in `~/.notchboard/snapshots/` with menu-bar restore, and a **`.notchboard` file association** (double-click imports; single-dot extension because LaunchServices can't associate multi-dot ones).

An export protects the *secret-typed values* and nothing else: usernames, element names, notes, schema, environments and the claimant's display name are readable plaintext in the file. That is a reviewed, accepted trade-off (vision.md §13.9/§14.7) — being able to open a collection file and read it is worth real debuggability. The per-field lever is the field type: mark a field `secret` and it moves into the encrypted envelope. A file is exactly as strong as its export password, which is why the prompt offers a generator.

Secret values never sit in plaintext in any file: `state.json` holds Keychain placeholders, exports hold ciphertext, snapshots are sealed whole. `NBGroup.secretFieldKeys` is the single definition of which fields are secret, and `NBWorkspace.mappingSecretValues` is the single traversal that pairs it with element values — the export envelope fill, the import force-blank + inject, and the placeholder swap all go through it. The import trust boundary lives in `WorkspaceTransfer.readFile`/`unlockingSecrets`: in-band secret values are force-blanked whatever a file claims, and real values only enter through the authenticated envelope. Changing a field away from the secret type drops its value and Keychain entry, blanking a secret deletes its entry, and orphaned entries are swept at launch — with the keeping-set spanning **all** collections (`Array<NBCollection>.allSecretKeychainKeys`; passing one collection's keys would silently delete the others' secrets).

One deliberate, documented exception to the secrets posture: `simctl` takes the deeplink URL as a command-line argument, so a password passed in the query is visible in the process list to other processes running as you while that short-lived process runs. There is no argv-free way to hand `simctl` a URL. See the header of `Docking/SimctlBridge.swift` — everything under the app's own control (its log lines, and `simctl`'s echoed stderr) is redacted.

## Verification status (2026-08-07)

195 tests pass (including the `SimctlBridge` integration suite against a booted simulator, which self-skips when none is booted — boot one before trusting a green run), Release builds with zero warnings in app sources, and every shipped feature has now been exercised **by hand** from a wiped state — onboarding's three starting points, collection CRUD and switching, the per-collection deeplink scheme, encrypted export/import (right password, wrong password, skip path), snapshot restore, and "login on sim" against `SampleApp/NotchDemo`. See vision.md §13.9. Nothing is known-broken; what follows is debt and accepted trade-offs, not defects.

## Known issues (as of 2026-08-07)

- `NotchboardViewModel` is down to ~886 lines after the 2026-08-07 decomposition, which is coordination rather than a god object, but still large. The two remaining coherent seams, if it needs to shrink again: the claim lifecycle (`claimOrRelease`/`takeOver`/`releaseExpiredClaims`/notify, ~110 lines) and the deeplink bridge (`loginOnSim`/`copyAuthAndClaim`/credential lookups, ~130 lines). Both were left in place deliberately — each needs the store, identity, toasts and the clipboard, so extracting them now would produce anemic types with four dependencies rather than a real boundary. Revisit when sync gives claims a second driver.
- No SwiftFormat config. SwiftLint config exists but runs advisory in CI, with warnings not yet burned down.
- Claim-age labels update on re-render (the 30s auto-release sweep triggers them), not on a per-minute tick of their own.
- `secondaryText` still special-cases `group.id == "promos"`/`"products"` for row subtitles (guarded on the fields existing). Known debt; the login button was made schema-driven.
- Cross-machine catalogue moves now work via encrypted exports (import + password restores secrets). `state.json` itself still doesn't travel: on a machine without the matching Keychain, secret fields load empty. A Keychain *read error*, as opposed to a missing item, keeps the placeholder rather than persisting an empty value. Snapshots don't travel either — their sealing key is device-local by design.
- No presence: claims by other people can't update live (that's the deferred sync milestone, vision.md §14). Identity itself is real now — a persisted `memberID` with the onboarding name as claim label.
- AppKit accessory views in `NSAlert` prompts must not use `NSStackView`: it lays out with Auto Layout, and an empty `NSTextField`'s intrinsic width is a few points, so the export password field collapsed to a sliver and the password was invisible. `PromptAccessory` composes plain containers with fixed frames instead, and `PromptAccessoryTests` forces layout to keep it that way.
- Timing-sensitive tests must poll rather than wait a fixed interval. The whole suite is main-actor isolated, so a heavy neighbour (PBKDF2, AES, snapshot IO) can delay a main-actor continuation well past a hard-coded deadline — that made the claim-tooltip test fail only in full runs, which reads as a product bug and isn't one.
