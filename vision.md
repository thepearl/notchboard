# Notchboard — Vision

> Source of truth for this analysis: `Notchboard Prototype.dc.html` (interactive prototype, 742 lines,
> full state machine) and `Notchboard Explorations.dc.html` (direction-selection doc — "chosen direction:
> dev-tool carbon 1b"), both under `~/Downloads/Notchboard test data companion/`.

## 1. One-liner

**Notchboard is a macOS utility that docks to the iOS Simulator window and gives a mobile team one
shared, live catalogue of test accounts and fixtures** — so nobody has to ask "does anyone have a
working login for X?" in Slack again.

## 2. Problem it solves

Mobile teams accumulate dozens of test accounts and fixtures (empty-state users, premium users,
broken-payment users, promo codes, product SKUs with edge-case stock/pricing) scattered across
notes apps, Slack threads, and tribal knowledge. Two failure modes recur constantly:

1. **Discovery cost** — "which account triggers the empty cart state again?"
2. **Collision cost** — two QA engineers unknowingly use the same account in parallel and pollute
   each other's test session (e.g. both testing checkout on the same "No Payment Method" user).

Notchboard fixes both by being a **live, shared, claimable catalogue** that sits physically next to
the Simulator, not in a separate app you have to alt-tab to.

## 3. Target users

- iOS engineers and QA on a team (3–15 people is the implied scale: "4 online", "21 elements").
- Teams already running the iOS Simulator locally during manual/exploratory testing.
- Teams comfortable granting a macOS Accessibility permission to a small utility (RocketSim is the
  explicit trust anchor referenced in the onboarding copy: *"same pattern RocketSim uses — a known,
  App-Store-approved approach"*).

## 4. Core mechanic: docking to the Simulator

Notchboard is not a normal window. It uses the macOS **Accessibility API (AXUIElement)** to locate
the running `Simulator.app` window and physically attach itself to its right edge, tracking it as it
moves/resizes. This is the same class of technique RocketSim uses, and the prototype's onboarding
step 4 explicitly names that permission and precedent.

Two visual states:

- **Collapsed ("the notch")** — a slim vertical tab flush against the Simulator's right edge: amber
  square glyph, a small pulsing green dot + claimed-count readout, a `»` affordance. Click to expand.
- **Expanded (the panel)** — a 404×592 dark panel docked immediately to the right of the Simulator
  window, containing the full catalogue UI.

If Accessibility permission is ever denied or the Simulator isn't running, the explorations doc
flags a **menu-bar fallback** as the next thing to design — i.e. v1 should not hard-depend on
successful docking to be usable at all.

## 5. Feature breakdown (from the working prototype)

### 5.1 Onboarding (first launch, 4 steps + progress dots, back navigation)
1. **Welcome** — brand pitch: *"shared test data, docked to your simulator"*.
2. **Identity** — user enters their name; this is what appears on every element they claim
   (`claimed by tom`). Live preview of initials/avatar as they type.
3. **Join workspace** — paste an invite code (`NB-XXXX-XXXX`). On a valid-looking code (≥6 chars),
   resolves to a workspace card: name, member count, group count, element count, stacked avatars.
   A `create a new workspace instead` link exists but is explicitly stubbed as **phase 2**.
4. **Accessibility permission** — request the AX grant needed for docking; button unlocks once
   granted.

On completion: dock happens, a **coach mark** appears near the notch (*"docked ✓ ... click the notch
to open the team catalogue"*), and a background **presence simulation** starts (see 5.5).

There's also a persistent "replay onboarding" affordance for demoing/support purposes.

### 5.2 Catalogue — List view
- **Environment filter**: `ALL / DEV / STG / PRD` chips, color-coded (DEV blue, STG amber, PRD red)
  — filters the current group's elements.
- **Search**: `⌘K` opens the panel and focuses search from anywhere; searches name, note, and all
  field values of the active group.
- **Group tabs**: groups are **user-defined, not hardcoded** (seed data ships with `users`,
  `products`, `promos`, but a `+ new group` action creates arbitrary new ones with their own schema).
- **Rows**: favorite star (toggle), primary name, secondary field (schema-driven — e.g. username for
  users, SKU+price for products, discount%+expiry for promos), a **claim badge** when in use
  (pulsing dot + claimer name, hover reveals a tooltip with claim age, auto-release countdown, and a
  "notify when free" action), env badge, one-click copy of the primary field.
- **Empty state**: "no elements match — clear filters or + add one".
- **Footer**: live claimed count, "sync Ns ago" freshness indicator, "+ new {type} ⌘N".

### 5.3 Catalogue — Detail view
- Back nav, name + favorite toggle, claim status line (`● claimed by tom · 14m` / `○ free`), env
  badge.
- **Schema-driven field rows**: each field from the group's definition renders as a
  label/value/copy row; `secret`-typed fields render masked (`••••••••••`) with a reveal/hide
  toggle, independently tracked per element+field.
- Free-text `note` and `last used` rows (always present, not part of the schema).
- **Claim / release button** — claiming an unclaimed element assigns it to "you" and copies its
  primary field; releasing (only if you're the claimant) frees it; clicking a claim owned by someone
  else surfaces a toast nudging you to ping them or claim anyway.
- **"⚡ Login on sim"** (users group only) — fires a debug deeplink into the booted Simulator via
  `xcrun simctl openurl booted "<scheme>://debug/login?user=..."`, auto-claims the element if free,
  and — in the prototype — drives a **scripted phone-screen animation** (login form fills in,
  spinner, home screen) to demonstrate the target app receiving and honoring that deeplink. Labeled
  **phase 3** in the UI copy.

### 5.4 Add-element view
Dynamic form generated from the active group's field schema (label, type-aware placeholder) plus the
universal `display name`, `environment` picker, and optional `note`. Validates a name is present
before creating; new elements sync instantly and show a success toast.

### 5.5 New-group view (schema designer)
This is the most structurally important feature: teams can define **arbitrary data shapes**.
- Group name input.
- A reorderable list of fields (drag handle, editable label, type dropdown: `text / secret / number
  / bool / date / url / picker`, remove button).
- "+ add field" to append more.
- On create: slugifies the name into a group id, derives field keys, sets the first field as the
  row's "secondary" display value, and switches the panel into that new group.

### 5.6 Presence / real-time simulation
The prototype simulates teammates claiming/releasing elements on a timer (Sara releases a user at
9s, Mia claims one at 17s, etc.), each surfaced as a toast. This is stand-in for what must be a
**real shared backend** in production — Notchboard's core value (*one live catalogue for the whole
team*) only exists if state genuinely syncs across machines in near-real-time, not just within one
session.

### 5.7 Toasts & shortcuts
- Bottom-right toast stack (copy confirmations, claim/release events, validation errors, deeplink
  fired, etc.), amber/green/red coded, auto-dismiss ~2.8s.
- Keyboard: `⌘K` → open + focus search, `Esc` → back to list view, `⌘N` implied for "add new".

### 5.8 Configurable behavior (already modeled as props in the prototype)
| Setting | Type | Default | Notes |
|---|---|---|---|
| `skipOnboarding` | bool | `true` (in prototype only, for demoing) | Would be `false` for real first-run |
| `startExpanded` | bool | `true` | Whether the panel opens expanded vs. collapsed to the notch |
| `presenceSim` | bool | `true` | Prototype-only fake presence; in the real app this becomes "enable live sync" |
| `autoReleaseMins` | int (5–240, step 5) | `60` | Idle claim auto-release timer |

These map directly to a real **Settings** surface in v1.

## 6. Data model (as implemented in the prototype's state)

```
Workspace
├─ groupOrder: [groupId]              // ordered tabs
└─ groups: { [groupId]: Group }

Group
├─ label, singular                    // "users" / "user"
├─ secondaryKey                       // which field shows as the row subtitle
└─ fields: [{ key, label, type }]     // type ∈ text|secret|number|bool|date|url|picker
   elements: [Element]

Element
├─ id, name, env (DEV|STG|PRD), fav: bool
├─ claimedBy: { who, mins } | null
├─ note: string, last: string (human "last used" string)
└─ values: { [fieldKey]: string }     // schema-driven payload

Member  (team roster referenced by claims)
└─ { id, name, short }                // e.g. tom → "Tom Verhoeven"
```

Seed content in the prototype (Brewly, a fictional coffee-subscription app) is purely illustrative
of the "users / products / promos" pattern — the real product must not assume any fixed group set.

## 7. Visual design system (locked direction: "dev-tool carbon")

- **Palette**: background `#0c0e11`, panel `#111318`, borders `#23262d`/`#2a2e37`, primary text
  `#f0efec`/`#e8e7e3`, secondary text `#5b6270`/`#8a92a3`, muted `#464d5a`.
- **Accents**: amber `#ffb454` (brand + primary actions), signal green `#3ddc84` (presence/success/
  claimed), red `#ff6b6b` (danger/PRD/secret-type/errors), env colors DEV blue `#7ab8ff` / STG amber
  `#ffb454` / PRD red `#ff6b6b`.
- **Type**: Space Grotesk for headers/UI labels, JetBrains Mono for all data, keys, badges, and
  monospace-flavored microcopy.
- **Texture**: faint 36px grid background, sharp 3px radii on data rows vs. slightly softer 6–10px
  on panels/cards, subtle motion (fade-in, panel slide-in-from-left, claim-dot pulse, toast slide-up)
  — nothing bouncy, everything quick (~150–300ms).
- This direction was explicitly chosen over alternatives in the explorations doc ("1b" locked in).

## 8. Explicit phasing already encoded in the prototype's own copy

- **Phase (implicit, foundational)** — window docking to Simulator via Accessibility API, onboarding,
  join-workspace-by-code, browse/claim/search/add elements, custom group schemas. This is the MVP.
- **Phase 2** — "create a new workspace" flow (today only joining via invite code is supported).
- **Phase 3** — the `⚡ login on sim` deeplink action that actually drives the target app via
  `simctl openurl` and a `debug/login` URL scheme convention.
- **Noted as a next exploration, not yet designed** — a **menu-bar fallback** presentation for when
  docking isn't possible or desired.

## 9. What this means for the native macOS implementation

The prototype is a browser mock of interaction and visual design only — it has no real networking,
no real Accessibility API, and no real Simulator control. Building it natively means:

1. **Window architecture**: a borderless, non-activating `NSPanel` (so it never steals focus from
   Simulator/Xcode), floating at a level above normal windows, positioned relative to the tracked
   Simulator window frame; app runs as an agent (`LSUIElement`) with a menu-bar icon as the always-
   available entry point/fallback per the explorations note.
2. **Docking engine**: `AXObserver`/`AXUIElement` to find `Simulator.app`, read its frame, and
   subscribe to move/resize notifications to keep the notch/panel glued to its edge; graceful
   degradation to a menu-bar-only mode if permission is denied or Simulator isn't running.
3. **Sync backend**: the "shared, live" promise is the entire value proposition, so this cannot be
   local-only. Needs a lightweight real-time backend (workspace/group/element/claim CRUD + a realtime
   channel for presence and claim state) — e.g. Supabase (Postgres + Realtime + Auth) or Firebase, or
   a small custom WebSocket service, chosen based on team's existing infra preferences.
4. **Deeplink bridge (phase 3)**: shell out to `xcrun simctl openurl booted "<url>"`; requires a
   documented convention the target app must adopt for a debug URL scheme, and Simulator must be
   booted — needs clear failure states (no booted simulator, target app not installed, scheme not
   registered).
5. **Global shortcuts**: `⌘K`/`⌘N`-style shortcuts must work while the app doesn't have key focus —
   requires a global hotkey mechanism (e.g. `NSEvent` global monitor or a small hotkey library),
   since the panel is meant to be glanceable without breaking your flow in Xcode/Simulator.
6. **Secrets handling**: values marked `secret` (e.g. passwords) are masked by default with explicit
   reveal — even though these are shared *test* credentials, not real user data, the product should
   still avoid rendering them in cleartext in view hierarchies/logs by default, and consider at-rest
   encryption for the synced store.
7. **Settings**: expose `startExpanded`, `autoReleaseMins`, `presenceSim`(→ "live sync enabled"), plus
   real settings the prototype doesn't need (server/workspace connection, notification prefs for
   "notify when free", global hotkey rebinding).

## 10. Non-goals for v1

- No support for creating a brand-new workspace from scratch (phase 2 per the prototype's own
  copy) — v1 ships with join-by-invite-code only; workspace creation can be admin/CLI/dashboard-side
  initially.
- No deep simulator automation beyond firing one deeplink (phase 3) — no fixture seeding, no full
  device state reset, no multi-step scripted flows.
- No Android/emulator support — Simulator (iOS) only, per all prototype references (`Simulator.app`,
  `xcrun simctl`, iPhone 16 Pro chrome).
- No permission model beyond "everyone in a workspace sees/edits everything" — no roles, no
  per-group ACLs, no audit log in the prototype; if needed, treat as a v2 concern.

## 11. Open questions to resolve before/while building

1. **Sync backend choice** — Supabase vs. Firebase vs. custom service; drives auth (invite codes →
   real workspace auth), realtime claim broadcast, and secret storage approach.
2. **Auth model** — is "your name" (onboarding step 2) the whole identity, or does it need to map to
   a real account (email/SSO) for security and to prevent claim spoofing?
3. **Multi-app support** — prototype hardcodes one fictional app's deeplink scheme
   (`brewly://debug/login`); real product needs a per-workspace configurable scheme + a documented
   integration contract for teams to adopt in their own app's debug builds.
4. **Menu-bar fallback design** — flagged as unstarted in the explorations doc; needed for users who
   deny Accessibility access or don't want docking.
5. **Conflict resolution** — what happens when two people edit the same group schema concurrently,
   or claim the same element in the same instant (race condition in "claim + copy")?
6. **Distribution** — App Store (like RocketSim) vs. direct download; affects sandboxing constraints
   on the Accessibility API and `simctl` shell-out.

## 12. Suggested build order

1. Native window/docking shell (menu-bar agent app, AX-based Simulator tracking, collapsed/expanded
   states) with **static/local mock data** matching the prototype's schema — get the "feel" right
   first.
2. Visual system pass (colors, type, motion) matching §7 exactly, since the direction is already
   locked and validated.
3. Local-only catalogue CRUD (groups, elements, custom fields, claim/release with local
   auto-release timer) — no backend yet, single-user.
4. Onboarding flow (steps 1–2 only: welcome + identity) + settings surface.
5. Real backend integration: workspaces, invite codes, realtime claim/presence sync (this unlocks
   onboarding step 3 for real and makes the product's core promise true).
6. Accessibility permission step (onboarding step 4) wired to the real docking engine from step 1.
7. Phase 2: create-workspace flow.
8. Phase 3: `simctl openurl` deeplink bridge + integration docs for target apps.
9. Menu-bar fallback mode for no-Accessibility / no-Simulator states.

## 13. Implementation status (as of 2026-08-06)

This section documents what actually exists in the `notchboard/` Xcode project today, as a
running log — update it as the build evolves so it stays the source of truth for "what's real
vs. still vision."

### 13.1 What's implemented

- **Real docking to the Simulator window** (not a mock). `Docking/SimulatorWindowTracker.swift`
  polls (~3x/sec) for a running process with bundle id `com.apple.iphonesimulator`, reads its
  frontmost window's frame via the Accessibility API (`AXUIElementCopyAttributeValue` for
  `kAXPositionAttribute`/`kAXSizeAttribute`), and converts AX's top-left-origin coordinates to
  AppKit's bottom-left-origin screen coordinates.
- **A real floating panel, not a normal window.** `AppDelegate.swift` runs the app as an
  accessory (`NSApp.setActivationPolicy(.accessory)` — no Dock icon, no Cmd-Tab entry) and hosts
  all UI in a borderless, non-activating `FloatingPanel` (`NSPanel` subclass overriding
  `canBecomeKey` so text fields/keyboard shortcuts still work despite being non-activating).
  The panel is transparent (`isOpaque = false`, `backgroundColor = .clear`) so only the actual
  notch/panel/dialog shapes are visible — no background rectangle, no grid, no fake phone.
- **Docked lifecycle**: the panel now mirrors the Simulator's presence, not just its position.
  If Simulator quits or has no window, the panel fades out and hides (`orderOut`); the moment
  Simulator is running again, it fades back in and redocks automatically. Onboarding is the one
  exception — it's shown regardless of Simulator state, since first-run setup shouldn't require
  Simulator to already be open.
- **Real Accessibility permission flow.** Onboarding step 4's "grant access" button calls
  `AXIsProcessTrustedWithOptions` with the prompt option (`Docking/AccessibilityPermission.swift`)
  to trigger the actual system dialog, and polls `AXIsProcessTrusted()` while that step is visible
  to detect once the user flips the toggle on in System Settings.
- **Animated, mode-aware resizing.** The panel snaps instantly to follow the Simulator window
  while it's being dragged/resized (no lag), but animates smoothly (`NSAnimationContext`,
  ease-in-ease-out, ~0.22s) whenever the actual *content mode* changes — collapsed notch ↔
  expanded panel ↔ notch-with-coach-mark ↔ onboarding dialog. The SwiftUI side mirrors this with
  matching opacity+scale transitions so the window resize and the content crossfade feel like one
  motion instead of two separate things happening.
- **Full interactive catalogue UI** against local mock data matching the prototype's schema
  exactly (see `Models/MockData.swift`): browse/search/filter by env, favorite, claim/release with
  hover tooltip (claim age + auto-release countdown + "notify when free"), schema-driven detail
  view with secret reveal, add-element form, and a new-group schema designer (field label/type
  editor). All local state only — see §13.2.
- **4-step onboarding** (welcome → identity → join-workspace-by-code → Accessibility permission)
  with progress dots and back navigation, plus a coach mark shown next to the notch right after
  finishing onboarding.
- Toasts render as an overlay on *whatever* content is currently showing (including during
  onboarding — this was a real bug we hit and fixed: validation-error toasts were being created
  but never rendered while the onboarding dialog was up, which looked like "nothing happens" when
  clicking a button that should have shown an error).
- **Hardening pass (2026-07-20, post-audit).** Secret-typed field values are stored in the
  Keychain (`SecretsStore`) and never written to `state.json`; copying a secret marks the
  pasteboard with `org.nspasteboard.ConcealedType`. Persisted state carries a schema version,
  decodes settings leniently, is saved debounced (flushed on quit), and a corrupt file is backed
  up rather than silently discarded. `activeGroup` no longer force-unwraps, and restored state is
  sanitised (`groupOrder`/`groups` reconciled) so a hand-edited state file can't crash the app.
  **Claim auto-release is real**: claims store a `claimedAt` date, ages tick live, and a 30s
  sweep releases claims older than the configured `autoReleaseMinutes`. AX reads run off the
  main thread (a busy Simulator can't freeze the UI) and the top-left→bottom-left coordinate
  flip uses the true primary screen, fixing docking when Simulator lives on a secondary display
  of a different height.
- **Full CRUD, 2026-07-20.** Elements can be edited and deleted; groups can be renamed, have
  their schema edited, and be deleted, with element values preserved across a relabel via stable
  `NBField.id`s. Workspaces export and import as versioned JSON (secrets stripped both ways).
  Notify-when-free fires a local notification. The list has arrow-key navigation, and there are
  launch-at-login and dock-edge (left/right) settings.
- **The `simctl` deeplink bridge is real** (superseding what §13.2 claimed for a while):
  `Docking/SimctlBridge.swift` runs `xcrun simctl openurl booted <url>`, and `loginOnSim` fires
  `<scheme>://debug/login?user=…` with the scheme configured in Settings, auto-claiming the
  element only once the deeplink actually succeeded. `copyAuthAndClaim` is the fallback for
  logins a deeplink can't drive (SSO/WebView).
- **The menu-bar fallback is real** (also superseding an outdated §13.2 note): a status item
  offers expand/collapse, "Show Panel (Undocked)" for when Simulator or Accessibility is
  unavailable, replay onboarding, export/import, Settings, and quit.
- **Correctness and hardening pass (2026-08-06, post-audit).** A full audit found 25 verified
  defects; all are fixed. The ones worth remembering:
  - The onboarding permission poll swallowed `CancellationError` from `Task.sleep`, so leaving
    step 4 turned it into a zero-delay main-actor spin for the rest of the session. Cancellation
    must exit that loop.
  - Continuous animation in the panel is expensive in a way that is structural, not incidental —
    see §13.4.
  - Global shortcuts were rebuilt on Carbon `RegisterEventHotKey` so the chord is genuinely
    consumed (see §13.5). They are also gated on the panel being genuinely visible, so they
    can't mutate a hidden panel whose stale state surfaces later, and re-invoking the add form
    no longer wipes an in-progress draft.
  - Deleting the last group then adding an element used to mint a phantom group keyed `""` that
    the group editor then refused to touch. Mutations now resolve the real group id.
  - A failed Keychain write no longer leaves a placeholder in `state.json` pointing at nothing
    (that turned a locked keychain into permanent loss of the secret), blanking a secret now
    deletes its Keychain entry, and orphaned entries are swept at launch.
  - Field keys are deduped on the create path as well as the edit path — "user id" and "user-id"
    used to collide into one value slot, and a secret aliased by a text twin was shown in clear.
  - Imported and hand-edited files get duplicate element IDs remapped and duplicate `groupOrder`
    entries removed.
  - The deeplink scheme is validated, so pasting a universal link can no longer fire credentials
    as query parameters at a real host; the auto-claim resolves the element's owning group
    captured at fire time, so switching tabs mid-flight no longer drops it.
  - The panel no longer flashes at the screen corner on launch, the onboarding dialog no longer
    teleports between displays as the cursor moves, mode-transition animations are no longer
    cancelled by the reposition timer, the docked frame is clamped to the screen so a fullscreen
    Simulator can't push the notch off it, and the left dock edge is properly mirrored.
  - "Notify when free" was unreachable by mouse (the popover dismissed as the cursor travelled
    toward it) and now has a grace period plus a second entry point in the detail view.
- **A test target exists** (`notchboardTests`, Swift Testing): 55 tests over the view models,
  persistence, Keychain round trip, deeplink logic, docking maths, and a guard against
  reintroducing the idle-animation regression. `xcodebuild … test` runs them, and CI runs build,
  test, and SwiftLint.

### 13.2 Deliberate simplifications / known gaps (still local-only)

- **No backend.** Workspace/groups/elements/claims all live in one `@Observable` view model
  seeded from `MockData.swift`. Multiple "teammates" claiming things, presence, and sync are not
  real yet — see vision §9/§11 for what a real backend needs to cover. This is the next phase.
- **No presence.** The prototype's simulated teammate activity was never ported, and the header
  now shows an honest member count rather than a fabricated "4 online". Other members' claims are
  static seed data, and the auto-release sweep only touches your own claims.
- **Claims are attributed to the literal string "you".** The onboarding name is persisted but not
  yet used as the claimant label; that needs real identity, which needs the backend.
- **Polling, not event-driven.** Both the Simulator tracker and the panel's reposition loop use
  `Timer` polling (~3–7x/sec) rather than `AXObserver` notifications or `NSWorkspace` run/terminate
  notifications. Simpler to implement and fast enough to feel live, but a real AXObserver-based
  approach would be more efficient and is a reasonable follow-up. (The AX reads themselves run
  off the main thread, the multi-monitor coordinate conversion was fixed in the 2026-07-20
  hardening pass, and the tracker's property writes are now equality-guarded so the poll can't
  re-render observing views at poll rate.)
- **Onboarding "join workspace" step is cosmetic.** Any code ≥6 characters shows a "found
  acme-mobile" card; there's no real invite-code backend yet (this matches vision §8's phase-1
  scope, just noting it's still fully mocked). The card's counts are at least read from the
  workspace that actually loads, rather than hardcoded.
- **The deeplink password is visible in the process list while `simctl` runs.** `simctl` takes the
  URL as argv and there is no argv-free alternative, so this is an accepted, documented tradeoff
  for shared test credentials on a local dev tool rather than an oversight. Everything under the
  app's own control — its log lines, and `simctl`'s echoed stderr — is redacted.
- **`secondaryText` still special-cases two group ids** (`promos`, `products`) for row subtitles,
  guarded on the fields existing. Known debt.
- **`NotchboardViewModel` is still a god object** (~850 lines). Decompose it before backend work;
  the test target now makes that safe to do.

### 13.3 A hard-won gotcha worth remembering

The Xcode "App" template enables **App Sandbox** (`ENABLE_APP_SANDBOX = YES`) by default. A
sandboxed process's calls into the Accessibility API for *other* processes get silently
swallowed — `AXIsProcessTrustedWithOptions(prompt: true)` returns without ever registering a
pending request in `TCC.db`, so no system permission dialog ever appears and there's no error to
debug from. This is the same reason tools like Rectangle/RocketSim-style window managers aren't
sandboxed. We disabled App Sandbox in the project settings (`ENABLE_APP_SANDBOX = NO`) to fix
this — if this project is ever submitted to the Mac App Store, this is a hard constraint to
revisit (direct/notarized distribution outside the App Store is the more likely path, same as
most Accessibility-API-driven macOS utilities).


### 13.4 The panel's animation budget (measured)

Continuous animation inside the docked panel is far more expensive than it looks, and the reason
is structural rather than a badly written animation. The panel is a *transparent*, borderless
window (`isOpaque = false`, `backgroundColor = .clear`, plus a 70pt SwiftUI drop shadow), so every
animation frame makes the window server re-blend the whole 404×592 panel — shadow included —
against whatever is behind it.

One continuously pulsing 6pt claim dot therefore cost, in a Release build with the panel open:

| what was animating | CPU (one core, steady state) |
| --- | --- |
| pulse animating a shadow *radius* | ~30% |
| pulse animating opacity only | ~20% |
| pulse animating opacity, panel shadow removed | ~8.5% |
| nothing animating | ~0.1% |

So the shadow amplifies the cost roughly 2.5×, but even an opacity-only animation is expensive,
and it ran for as long as the panel was open. The dot now pulses on hover and holds a steady glow
otherwise — hover is when "this claim is live" actually needs saying, and it is the moment the
user is looking at it. Idle cost is back to ~0.1%.

The rule this leaves behind: no continuous animation in the docked panel at rest, and animate
opacity rather than shadow radii or blur. `IdleAnimationGuardTests` fails the build if a
`repeatForever` animation appears without an interaction gate, because this regression is
invisible in a screenshot and only shows up as a warm laptop.

### 13.5 Global shortcuts: why Carbon, and why the chord is scoped

Reaching the catalogue from inside Xcode needs a shortcut that works while another app is
frontmost, and macOS offers two mechanisms with very different semantics. The API signatures
say it outright:

```swift
NSEvent.addLocalMonitorForEvents(matching:handler:)   // handler returns NSEvent?  → can swallow
NSEvent.addGlobalMonitorForEvents(matching:handler:)  // handler returns Void      → cannot
```

AppKit's own header is explicit that a global monitor "can only observe the event; you cannot
modify or otherwise prevent the event from being delivered to its original target application."
That is deliberate: a background app silently eating another app's keystrokes is a keylogger.

The first build used a global monitor for plain ⌘K/⌘N, which is why every ⌘N in Xcode opened a
new file *and* expanded Notchboard's add form. No handler-side logic can undo that, because the
double delivery happens before the handler runs.

So the shortcut now goes through Carbon's `RegisterEventHotKey`, which registers the chord with
the window server and genuinely consumes it. This is not an exotic choice. A survey of the
comparable open-source utilities found it universal:

| App | Mechanism |
| --- | --- |
| soffes/HotKey, sindresorhus/KeyboardShortcuts | `RegisterEventHotKey` (these are the two libraries most menu-bar apps depend on) |
| Maccy, Amethyst, MeetingBar | via KeyboardShortcuts |
| Ice | hand-rolled Carbon registry, no dependency |
| Rectangle | via MASShortcut |
| alt-tab-macos | `RegisterEventHotKey` for chords, plus a listen-only event tap for its bare-⌥ hold |

It also needs no TCC permission, unlike a `CGEventTap` (Accessibility) or an `NSEvent` global
key monitor (also Accessibility).

**The part that needed care.** A consumed chord is owned: while registered, nothing else on the
machine receives it. And the default chord here is a plain single modifier, ⌃K/⌃N, which the same
survey showed no comparable app dares ship as a default (Maccy, Clipy and Rectangle all use two
or three modifiers; Ice and MeetingBar ship no default at all). Worse, ⌃K and ⌃N are not obscure:
`/System/Library/Frameworks/AppKit.framework/Resources/StandardKeyBinding.dict` maps `^k` to
`deleteToEndOfParagraph:` and `^n` to `moveDown:` in every AppKit text field, and both zsh and
bash bind them to `kill-line` and `down-line-or-history`. Taking those machine-wide would be a
worse bug than the one being fixed.

The resolution is scoping rather than a safer chord. The registration is held only while:

1. the panel can actually respond (onboarding done, Simulator visible or the undocked fallback up), and
2. Xcode, Simulator, or Notchboard itself is the frontmost application.

Switch to Terminal and, on the next 0.15s tick, ⌃K is `kill-line` again. Rectangle uses the same
idea in reverse, unregistering its hotkeys while a user-chosen app is frontmost. The modifier is
also a setting (⌃ / ⌘ / ⌥⌘) with the cost of each spelled out in Settings, since which chord a
given developer can spare is not something the app can know.

One correction worth recording, because the first version of this code asserted the opposite:
registration failure does **not** mean another app holds the chord. With `inOptions: 0`,
`CarbonEvents.h` documents that several applications may register the same hot key and all be
notified. Failure means a duplicate registration inside this process, or a clash with a
`kEventHotKeyExclusive` holder.

### 13.6 The deeplink bridge, proven end to end (2026-08-06)

Until now the "⚡ login on sim" path had only ever been tested up to the `simctl` boundary: the
command ran and reported success, but no iOS app had ever received the URL and actually logged
anyone in. The product's headline feature was unverified.

`SampleApp/NotchDemo` closes that. It is a small SwiftUI app that registers `notchdemo://` and
handles `debug/login`, and it now serves two purposes: the standing target for dogfooding, and
the reference integration a real team would copy (see `SampleApp/README.md` — the whole
contract is an Info.plist entry and about ten lines in `onOpenURL`).

Verified on an iPhone 17 Pro simulator running iOS 26.4: the deeplink fills the login form and
signs in, and a second deeplink while already signed in swaps accounts cleanly.

Two things this surfaced that no amount of local reasoning would have:

- **iOS confirms the first deeplink.** Opening a custom scheme from outside the app raises an
  "Open in NotchDemo?" alert. It appears on the *first* deeplink only; afterwards the system
  remembers the choice and every subsequent login is instant. So the friction is one tap per
  simulator install, not per login — but a user who fires the feature once and sees a dialog
  could reasonably conclude the bridge is broken, which is worth saying in the UI eventually.
- **The bridge's own code is now covered against a real simulator**, not just stubbed.
  `SimctlBridgeIntegrationTests` fires `SimctlBridge.openURL` for real and asserts both the
  success path and that an unregistered scheme reports failure rather than silent success. It
  skips itself when no simulator is booted, and it has a timeout that fails loudly if the
  completion never arrives — which is exactly the hang the stderr-drain fix in §13.1 removed.
