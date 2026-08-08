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
session. *(Direction decided 2026-08-07: that sync arrives with no bespoke backend at all — see §14.)*

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
   **Superseded 2026-08-07:** no backend — sync rides MQTT retained messages on any standard
   broker; see §14.
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
   **Resolved 2026-08-07:** none of the above — no backend; sync rides any standard MQTT broker (§14).
2. **Auth model** — is "your name" (onboarding step 2) the whole identity, or does it need to map to
   a real account (email/SSO) for security and to prevent claim spoofing?
   **Resolved 2026-08-07:** in the core, a stable generated member id plus the onboarding display
   name, with the room password gating entry; real accounts/SSO are paid-tier triggers (§14.6).
3. **Multi-app support** — prototype hardcodes one fictional app's deeplink scheme
   (`brewly://debug/login`); real product needs a per-workspace configurable scheme + a documented
   integration contract for teams to adopt in their own app's debug builds.
4. **Menu-bar fallback design** — flagged as unstarted in the explorations doc; needed for users who
   deny Accessibility access or don't want docking.
5. **Conflict resolution** — what happens when two people edit the same group schema concurrently,
   or claim the same element in the same instant (race condition in "claim + copy")?
   **Resolved 2026-08-07:** last-write-wins per element/schema with timestamps and tombstones;
   claim races resolve by broker message ordering and presence (§14.2).
6. **Distribution** — App Store (like RocketSim) vs. direct download; affects sandboxing constraints
   on the Accessibility API and `simctl` shell-out.
   **Resolved 2026-08-07:** direct notarised download, never the App Store (sandbox-off is
   structural, §13.3), and the core goes open source (§14.1).

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

### 13.7 Sync and distribution direction decided (2026-08-07)

The backend question is settled — by removing the backend. §14 below is the constitution:
local-first, sync over MQTT retained messages on any standard broker, secrets end-to-end
encrypted under password-derived keys, an open source core, and a bespoke (paid) backend only
if the trigger list in §14.6 fires. Nothing in §14 was code at decision time; §13.8 records
the same-day implementation of every local milestone (collections, identity, encrypted
exports, snapshots, passphrase generator, file association). The MQTT room itself still
waits for a second user, per §14's own sequencing. Persona 3 (self-host) caveat resolutions
are deliberately parked; they are recorded in §14.4 and get decided another day.

### 13.8 The local milestones of §14, implemented (2026-08-07)

Everything §14 requires short of the room itself landed the same day the constitution was
written, in one pass (33 files, +2255/−198, tests 89 → 129):

- **Multiple collections.** `NBCollection` wraps `NBWorkspace` with a local-only id and a
  per-collection deeplink scheme; the view model holds `collections` +
  `activeCollectionID` behind a computed `workspace` facade, which let all three dozen
  call sites survive unchanged. Header switcher menu (switch/new/rename/duplicate/delete),
  import *adds* a collection, element-id uniqueness spans collections (Keychain account
  keys carry no collection component), and the launch orphan sweep keeps keys from **all**
  collections — the plan's named landmine, now guarded by a test.
- **Persistence in the collections shape.** `collections` + `activeCollectionID` +
  `memberID`, strict on the catalogue and lenient on settings. (A same-day migration path
  and downgrade shadow were built, verified live, and then removed again under the
  no-compat decision — see the amendment at the end of this section and §14.5.)
- **Identity (§14.2's prerequisite).** A persisted `memberID` that claims are attributed
  to, with the onboarding name finally labelling the user's in-use marks. The auto-release
  sweep now reaches background collections, and the deeplink auto-claim captures its
  owning collection so a mid-flight switch can't misroute it.
- **Encrypted exports (§14.5.1).** One export mode: a mandatory password (passphrase
  generator one click away, §14.5.3) seals all secret values into an AES-GCM envelope via
  PBKDF2 → HKDF (all platform primitives). Claims are stripped — a claim frozen into a
  file arrives stale by construction. Import prompts for the password with retry and an
  import-without-secrets skip path; in-band secret values are force-blanked whatever a
  file claims; a crafted envelope demanding an absurd KDF cost is refused. This retires
  the solo two-Macs caveat.
- **Snapshots (§14.5.2).** Periodic encrypted snapshots of all collections in
  `~/.notchboard/snapshots/`, sealed under a device-local Keychain key held in its own
  service (out of the orphan sweep's reach), bounded rotation, menu-bar restore that
  first snapshots the current state so a mis-restore is itself reversible. Verified
  ciphertext-only on disk.
- **File association.** `.notchboard` is the extension — deliberately single-dot, since
  LaunchServices resolves multi-dot extensions by their last component and could never
  associate a ".something.json" spelling — declared via a root-level partial Info.plist
  merged into the generated one, the same trick NotchDemo needed for the same reason.
  `open file.notchboard` was verified routing into the running app, importing as a new
  collection.

Runtime verification (headless): two files imported as collections two and three with ids
kept unique, the snapshot appeared encrypted, relaunch produced no corrupt backup, and the
live state was then restored byte-for-byte. (The migration was also verified live before
its same-day removal.) Not visually exercised: the password prompts, the switcher menu,
and snapshot restore — flagged in CLAUDE.md's known issues for the next dogfooding session.

### 13.9 First hands-on pass, and what it changed (2026-08-07)

Ghazi ran the hands-on list against the build. Onboarding, the collection switcher and
identity all checked out. Two things blocked the rest, and both were real:

- **The export password was invisible.** The prompt's accessory view used an `NSStackView`,
  which lays out with Auto Layout, so the empty `NSTextField` collapsed to its (near-zero)
  intrinsic width beside the Generate button. Rebuilt with a plain container and fixed
  frames; `PromptAccessoryTests` now forces layout and asserts the field survives it.
- **The per-collection deeplink scheme was unfindable.** It only existed in the Settings
  window, which is nowhere near the moment you notice it's missing. It is now an item in
  the collection ▾ menu showing the current scheme, validated on entry (a pasted universal
  link is refused rather than stored), with the detail-view hint pointing at it.

The same pass produced six UI changes, all from real use:

- **Legibility.** The grey scale was too dark to read — `textSecondary` and `textMuted` sat
  near 2.5:1 against the panel. Every step was lifted past 4.5:1 and the default mono label
  went 8pt → 9.5pt. The favourite star grew from 10pt to 13.5pt with a real hit area.
- **Detail actions.** The bottom "edit / delete…" pair read as one two-tone control and ate
  a screenful. They are now a ⋯ menu beside the environment badges, with delete confirmed
  by a proper dialog instead of a two-step inline button.
- **Multi-environment elements.** `NBElement.env` became `environments: Set<NBEnvironment>`:
  the same account normally exists in dev *and* staging, and a single value forced
  duplicate rows. Filtering matches any member of the set, and rows/detail render every
  badge.
- **A speed bump on production.** Selecting PRD alongside another environment raises a
  warning explaining how a prod credential reaches a debug build, with "I understand" and a
  native suppression checkbox whose answer is persisted.
- **Field types mean something.** `bool` is a two-state selector, `picker` is a real menu
  driven by new `NBField.options` (edited in the group designer), `number` filters
  non-numeric input as you type, and `url`/`date` are validated on save with a locale-
  independent format. `NBFieldValidation` is the gate, because imports and hand-edited
  files bypass any control.

Note for anyone reading the log later: this pass changed `NBElement` and `NBField`, so
every `state.json` and export written before it resets — the no-compat rule (§14.5) working
as designed rather than a defect.

**Retested the same day, all green.** From a wiped state (no `state.json`, no snapshots)
Ghazi walked the full list: onboarding and its three starting points, adding real elements,
the collection switcher (create/rename/duplicate/delete), the per-collection deeplink
scheme, encrypted export with the generated passphrase, import with the right password /
a wrong one / the skip path, snapshot restore, and "login on sim" against NotchDemo.
Nothing outstanding. This is the first time every shipped feature has been exercised by
hand rather than only by tests.

**Export format inspected, not just trusted.** He renamed a `.notchboard` file to `.txt`
and read it. What the plaintext showed, and why each part is right:

- `"password": ""` — the secret-typed value was pulled out and sealed; no credential is in
  the clear anywhere in the file.
- no `claimedBy` key — claims are stripped on export, as §14.5 requires.
- `secrets` carrying a 16-byte random salt, 600 000 PBKDF2-HMAC-SHA256 rounds and an
  AES-GCM combined box — so a tampered file fails closed and a wrong password fails
  cleanly rather than decrypting into plausible garbage.
- everything else readable: usernames, element names, notes, the schema, environments,
  collection name, and the claimant's display name inside `lastUsed`.

That last line is the accepted trade-off, and it settles §14.7's "encrypt all payloads?"
question **for now**: the split stays as it is, because being able to open a collection
file and see what's in it is worth real debuggability — and it is the same property the
future MQTT room design leans on. Two things change the answer: a catalogue holding a real
client's identifiers rather than test accounts, or the first complaint from a security
review. Until then the lever available without any code change is per-field: mark a field
`secret` in the group designer and it moves into the envelope. Documented so nobody
re-derives it: the file is exactly as strong as the export password, which is what the
Generate button exists to make easy.

**Amended the same day (two remarks from Ghazi):**

1. *No compatibility code before first release* (now §14.5 decision 5). The v1→collections
   migration, the downgrade shadow, `NBClaim`'s pre-`claimedAt` decoding, the literal-"you"
   claim tolerance and rebinding, the newer-schema `state.json.v(N)` backup, and the
   `.notchboard.json` filename tag were all removed again hours after landing. Version
   stamps reset to 1 and are checked exactly on imports. A pre-collections `state.json`
   now takes the corrupt-backup reset path — by design, since the only user is its author.
2. *"claim" left the UI* (now §14.5 decision 6). Every user-facing string — detail status
   line, buttons, list footer, row tooltip, settings, onboarding preview, the
   notify-when-free notification body — now says "in use"/"use", found by an exhaustive
   sweep and pinned by the copy in place. Internal identifiers keep their names.

### 13.10 The MQTT room, implemented (2026-08-07)

§14.2 stopped being a sketch the same day §13.9's retest went green. The whole path from
"the store emitted a change" to "a second peer's catalogue converged over a real broker"
is code, in five phases that each landed with the full suite green (195 → 268 tests):

- **Phase A — the model can carry conflicts.** `NBElement` gained `updatedAt`/`updatedBy`
  (LWW with a deterministic tie-break), `NBGroup` a schema stamp, `NBWorkspace` real
  tombstones (a deletion is a message, not an absence — clearing a retained topic
  delivers nothing to a Mac that was offline, and its stale copy would resurrect the row)
  and a rename stamp. Every local mutation primitive in `CollectionStore` stamps and
  emits a `SyncChange` through a closure sink; the remote-apply extension
  (`CollectionStore+SyncApply`) mutates without ever emitting — echo suppression by
  construction, not by flag. LWW clamps future timestamps (a skewed clock must not win
  every conflict forever), preserves local `isFavorite` and `claimedBy` (personal state
  and claim-topic state never ride the element payload), and `applyRemoteClaim` inserts
  the claimant into `members` first — without that, `releaseOrphanedClaims` silently
  wipes every remote claim at the next launch. Claim writes go through a dedicated
  `setClaim` that does NOT bump the content stamp, or marking a row in use would beat a
  teammate's real edit. Local stamps truncate to wire precision (milliseconds), or two
  peers editing within one millisecond diverge permanently. The format stamps stay at 1
  — pre-release there is no version history to keep (§14.5): the old-shaped state.json,
  exports and snapshots simply fail decode and reset or refuse, which is the same
  outcome with no v1/v2 ledger accumulating.
- **Phase B — the engine, proven with no network.** `RoomSession` owns the connect
  sequence: subscribe, publish a non-retained barrier to its own sync topic (retained
  replay is delivered first, so the barrier's echo marks replay complete), buffer, apply
  in structural order (meta → schemas → elements → claims → presence — replay is
  unordered across topics and a claim can arrive before its element), then the
  first-connect asymmetry: an empty room is seeded from local state; a non-empty room
  REPLACES a never-synced collection (after a forced snapshot) — which is what keeps two
  teammates who imported the same file from double-pushing every row under re-minted
  element ids. Rejoins LWW-merge then reconcile-push (newer local edits, new local
  elements, offline deletions, claims made while away). The wrong room password is
  proven against one payload BEFORE the destructive adopt — GCM authenticates, so a typo
  fails loudly and touches nothing. A deterministic in-memory broker (`LoopbackBroker`,
  pump-based, no timing) drives 15 convergence scenarios; it caught two protocol-shaped
  bugs unit tests couldn't (subscriptions surviving reconnect turned every rejoin into a
  re-seed; adoption's own creation timestamp beat the room's legitimate rename).
- **Phase C — the real transport.** mqtt-nio (Apache-2.0) became the project's **first
  dependency**. `MQTTSyncTransport`: MQTT 5, clean start, QoS 1, TLS mandatory
  (`mqtts://`, `wss://` for corp firewalls; plain `mqtt://` refuses anything but
  localhost), keepalive 45 s (the "closed lid frees claims in a minute or two" number),
  exponential reconnect 1 s → 60 s, sleep/wake via NSWorkspace notifications, LWT = the
  sealed offline presence, stable client id `nb-<memberID>` so a second connect
  supersedes rather than ghosts. Two MQTT subtleties are load-bearing: noLocal only
  suppresses *live* echoes, so publishes hold until in-flight SUBACKs land (otherwise
  your own message comes back as retained replay), and a graceful disconnect flushes the
  outbox first (or the goodbye eats its own offline presence). The mosquitto integration
  suite (5 tests, self-skipping without a broker on :1883, the SimctlBridge pattern)
  proved retained round-trip/clear, the barrier echo, and the will firing on session
  takeover.
- **Phase D — the UI.** Room setup/join/leave in the collection ▾ menu beside the
  deeplink scheme (same per-collection, dialog-driven shape; password fields carry the
  Generate button, §14.5.3). Room passwords live in their own Keychain service
  (`flourix.notchboard.rooms`, out of the element sweep's reach, accounts hashed).
  The amber brand square in the header and the collapsed notch became the connection dot
  (`NBColor.syncState`: amber local/connecting, green live, red failed — never animated),
  with "n online" beside the switcher. A claim whose holder is offline *renders* free
  (" · offline" in the status line, button and tooltip) and using it is a deliberate
  takeover — the mark itself is never mutated by presence. Exports embed the room
  address (never the password, and never the local firstSyncCompleted flag); importing a
  file that carries one triggers §14.3's "join as <name>?" prompt, with "not now"
  keeping the address on the collection for a later join from the menu.
- **Phase E — verified end to end on one Mac.** `PeerHarnessTests`: two complete peers
  (store + engine + real MQTT transport) against local mosquitto walk the whole §14.3
  story — seed, adopt with re-minted ids, live edit, claim with presence and name
  attribution, delete, graceful goodbye rendering the mark free, and wake-up replay as
  the catch-up. 268 tests total, three consecutive full-suite runs green against a live
  broker, Release build zero warnings in app sources, runtime launch clean (0.1% CPU
  idle) with the v1 state.json taking the corrupt-backup reset exactly as designed.

Not yet exercised: a second *human* on a second Mac (the harness stands in), a managed
TLS broker (only local plaintext mosquitto so far — the `mqtts://` path is code-complete
but has never shaken hands with a real certificate), the `wss://` fallback, and the room
dialogs by hand. Those are the next dogfooding session's list.

Accepted rough edges, documented rather than hidden: a claim released while offline is
reinstated by its own retained twin on reconnect and ages out through the auto-release
sweep (a claim is a status light; a minute of staleness beat a special-case protocol);
broker-side tombstones expire after 30 days in step with the local prune, so a peer
offline longer can resurrect a deleted row; and LWW still silently drops one side of a
genuinely simultaneous same-element edit, §14.2's known trade with `automerge-swift` as
the escalation path.

### 13.11 The first two-human test (2026-08-08)

Ghazi and a colleague ran the QA plan (docs/room-test-plan.md) against the public EMQX
broker — the first time two people, two Macs and a real TLS handshake met the room. T1–T10
all passed: setup, export-as-invitation, import + join prompt, adopt, presence, live edits
both ways, schema propagation, attributed in-use marks, notify-when-free, login-on-sim.
The `mqtts://` path is no longer theoretical.

Five findings, all fixed the same day — four from the colleague's first-ever session,
which is exactly the fresh-eyes value a second human adds:

- **The room dialog's example hostname got typed in verbatim** (broker.example.com,
  ten-second timeout, red dot). No dialog copy shows an enterable-looking address any
  more; the placeholder is `mqtts://your-broker:8883`.
- **The list footer still said "· local" with a live room connected.** Pre-sync copy that
  never learned about rooms. It now reports the truth: local / live / connecting… / room
  offline / room unreachable, plus "n online" while connected.
- **"+ new user" read as a stray label in a weird place.** It is now a real amber button,
  top of the list beside the search field, labelled "+ new <singular> entry" — the word
  *entry* was the missing half of the sentence.
- **The production-mixing warning fired on every environment chip.** It now fires once,
  on save — the moment of commitment — with the copy cut to one line ("huge" was the
  colleague's word for the old version). Toggling while composing is prompt-free.
- **The notch "wasn't really helping".** Two rounds: the first replaced the rotated
  count with upright in-use/free/online counts at 36×190 — and Ghazi's same-day retest
  killed that too ("too big, the infos are not useful"). Final form is 36×110 (wider
  than the original 28, and shorter) showing exactly two things: the connection dot and
  the expand chevron. A lesson recorded for the next redesign impulse: the notch is a
  door handle, not a dashboard. Still nothing animates at rest.

Also added on request: a Settings toggle for notification sound (on by default — the
banner always shows, the ping is optional).

A sixth finding surfaced at the end of the session: switching to Chrome hid the
Simulator (normal window level) but not the panel (permanent `.floating` level), leaving
Notchboard visibly docked to a window that was no longer there. The panel now floats
only while Simulator (or Notchboard itself) is frontmost — narrowed from the chords'
Xcode-inclusive set on Ghazi's follow-up: "it's supposed to be with Simulator only" —
and drops to normal level otherwise, so the app the user switches to covers it exactly
as it covers the Simulator. Level changes ride app-activation notifications, not a timer.

The last polish of the session was follow latency: the panel trailed a dragged Simulator
window by up to half a second (a 0.35s AX poll stacked on a 0.15s reposition tick). The
tracker now polls adaptively — ~60Hz exactly while a drag is possible (Simulator
frontmost, mouse button down), 10Hz while it's merely frontmost, the old ~3Hz otherwise —
and fires a callback that repositions the panel the moment a frame lands. On top of
that, each sample is a short ease-out glide rather than a snap — retargeting mid-glide
interpolates the discrete AX samples into one continuous motion. Docked movement now
reads as part of the Simulator window rather than something chasing it.

### 13.12 One password to join: the invite redesign (2026-08-08)

The HiveMQ Cloud test (the first broker requiring an account) exposed the flow the
passwords had quietly piled up into: joining a team took a file plus three passwords in a
row — export, room, broker — and Ghazi's verdict was the right one: "people will leave if
it's so hard." Each password had a locally-good reason; nobody had re-run the joiner's
end-to-end experience since the room landed.

The fix came from noticing that §14.3's "the file is the invitation" predates the sync
implementation. The room already holds the whole catalogue as retained messages, secrets
sealed inside — a joiner with an empty collection adopts everything on first connect, so
the file was dead weight in the join path. Three moves, all shipped and tested the same
day (274 tests, invitee flow proven by an engine receiving the broker credential it was
never given in plaintext):

- **The broker password stops being everyone's problem.** It gates transport, not content
  (payloads are E2EE regardless), and the whole team shares one broker account by design
  (§14.3) — so it now lives AES-GCM-sealed under the room key inside `NBRoomConfig`,
  typed once by the host, unsealed by each joiner's engine. It travels in invites and
  exports as ciphertext; the Keychain's "broker" kind is gone. Bonus: a wrong room
  password now fails instantly (the seal won't open) before any connection attempt, so a
  bad join can't hammer the team's broker account.
- **The invite replaces the file.** One paste-able line (`notchboard-room:` + base64url
  of the room config) copied from the ▾ menu, carrying address, room and sealed
  credential. A joiner pastes it — via the menu's "join with an invite…", or the new
  onboarding starting point "join a team room" — and types exactly one password. The
  export file remains what it always really was: a backup, and the no-room sharing path.
- **Room password and file password stay separate — but never meet.** Merging them
  (rejected §14.7 idea) would make every backup file a room key. Instead each appears in
  exactly one flow, and the export prompt now says "file password" so three unrelated
  secrets stop all being "the password".

Joiner cost went from four artifacts to two (invite + room password); host invitation
went from export-and-share-three-secrets to copy-invite-and-share-one. Re-running setup
with the account fields left blank keeps the existing sealed credential, so a settings
visit doesn't demand retyping. Not yet exercised by a second human — the QA plan's setup
block (T1–T3) was rewritten around the invite and needs a fresh run.

### 13.13 The polish pass (2026-08-09)

Ghazi's first full run of the finished invite flow worked end to end (HiveMQ Cloud with an
account, a second collection joining from a pasted invite, mosquitto locally), which moved
the complaints from "does it work" to "does it feel finished". Twenty-odd findings in one
list; the ones that changed a decision rather than a number:

- **Notify-when-free never notified.** The permission prompt fired at launch, where a user
  with no idea what the app is denies it by reflex — and a denial is only reversible in
  System Settings. It is now asked for on the first click of "notify me when it's free",
  and a refusal aborts the watch loudly instead of arming something that can't fire.
- **The mystery circle.** Collapsed, the panel is 36pt wide, so any toast was clipped down
  to its own status dot — a circle floating beside the notch that people rightly read as a
  glitch. Toasts now render only when there is a panel to render them in; anything that
  must reach a collapsed user goes through macOS.
- **Two buttons that looked identical.** "use + copy" and "copy login + password · mark in
  use" differed only in what landed on the clipboard, and the second one's two-line
  clipboard was the wrong shape for a login form anyway. Now one button per field, in
  paste order: "use + copy" and "copy password".
- **"Show Panel (Undocked)" did nothing.** It was only consulted when no Simulator window
  could be found, so with Simulator running the menu item was inert. An explicit request
  now outranks docking.
- **⌘, opened an empty window** — SwiftUI's own Settings scene (`EmptyView`, kept only to
  satisfy the one-Scene requirement) claimed the shortcut app-wide. Its command group is
  removed and the panel's key monitor answers ⌘, with the real window.
- **Lecturing.** Every settings footer, the room dialog's preamble and the production-mix
  warning were cut to one or two lines, and the ellipsis dropped from action labels. The
  standing rule from this round: **explain the consequence, never the mechanism.** Nobody
  reads the third line.
- **A fake title bar with fake buttons.** Onboarding's three traffic lights were decoration
  that looked exactly like controls. Red quits for real now; the other two are visibly
  dimmed with tooltips, because a dead control that looks alive is worse than one that
  looks unavailable.
- **Delete-group was a button that became another button.** Confirmation belongs in an
  alert with the element count, and the destructive action belongs in the header, not at
  the bottom of a scroll view.

## 14. Distribution and sync: the constitution (decided 2026-08-07)

Binding product direction for how Notchboard reaches people and how state moves between
machines. Decided in the 2026-08-07 brainstorm; resolves open questions §11.1, §11.2, §11.5
and §11.6, and supersedes §9.3's assumption that live sync needs a bespoke backend. §13 logs
what is real — as of the decision date, none of this is built.

### 14.1 Principles

1. **Local-first, always.** Everything works offline on one Mac, with no account and no
   network. Sync is an upgrade, never a prerequisite.
2. **One code path, three personas.** Solo is the app with the room field empty; a team
   without infra and a self-hosting team differ by one URL. Any feature that would make the
   personas diverge (accounts, server-side state) belongs behind the trigger list (§14.6),
   not in the core.
3. **No backend, deliberately.** Sync rides MQTT retained messages on any standard broker — a
   managed free tier or the team's own container. There is no Notchboard server: nothing of
   ours to deploy, update, back up or breach, and the app cannot even tell which broker it is
   talking to.
4. **Secrets are end-to-end encrypted wherever they travel.** In a room: ciphertext under a
   key derived from the room password. In an export: ciphertext under a mandatory export
   password. At rest: the Keychain, as today. Plaintext secrets never leave a Mac.
5. **The file is the invitation, bootstrap and backup — never the sync channel.** Catalogue
   changes propagate live through the room; the `.notchboard` file gets you in, moves
   catalogues between machines, and gets you back up after a disaster.
6. **The broker is a rendezvous, not a source of truth.** Every member's Mac holds the full
   catalogue; any member reseeds an empty broker on connect. Losing the broker loses nothing.
7. **Open source core, MIT-leaning** (validate the licence choice with an adviser before
   publishing). The repo is the landing page — README and demo gif are launch features — and
   an app that takes the Accessibility permission and holds credentials needs source
   visibility to be trusted at all.

### 14.2 Sync design sketch

One room per collection. Topics, all retained:

```
nb/<room>/schema/<groupID>            group name, field schema, ordering
nb/<room>/el/<groupID>/<elementID>    element payload; secret values as ciphertext
nb/<room>/claim/<elementID>           {memberID, name, at}; empty payload = free
nb/<room>/presence/<memberID>         "online"; Last Will flips it on disconnect
```

- Late joiners receive the entire current state from retained replay — no history protocol.
- Claims held by offline members render as free: the live twin of `releaseOrphanedClaims`.
- Deletions publish tombstones, so a Mac that was offline can tell "deleted" from "never saw it".
- Conflicts are last-write-wins per element with timestamps. Simultaneous edits of the same
  element are the accepted rare loss; `automerge-swift` is the escalation path if that ever
  hurts in practice.
- Crypto: room password → PBKDF2 (stretch) → HKDF (derive) → AES-GCM (seal), all platform
  primitives (CommonCrypto/CryptoKit). The broker relays bytes it cannot read.
- TLS on 8883 is mandatory; MQTT-over-WebSocket on 443 is the corp-firewall fallback.
- Payloads carry a schema version and unknown keys are ignored — two app versions must coexist
  in one room.
- Connection failures surface loudly in the panel, never as silent staleness.
- Identity prerequisite: a stable generated member id plus the onboarding display name as the
  claim label. Lands with the collections Phase 2 regardless of sync.

Precedents, not novelty: Home Assistant's MQTT discovery (a device catalogue as retained
config messages), Zigbee2MQTT availability topics, OwnTracks (human presence over MQTT, with
a production iOS client).

### 14.3 The three personas (docs-level walkthroughs)

**Solo dev — two minutes, nothing hosted.** Download, open, onboard: name, Accessibility,
starting point (sample / empty / import). The panel docks to the Simulator; ⌃K searches, ⌃N
adds; groups and field schemas are user-defined; secret fields live in the Keychain. Set the
app's URL scheme and "login on sim" signs the Simulator in with one tap, with copy-and-claim
as the SSO/WebView fallback. Claims are personal "in use" markers. Export any time: the file
always includes secrets, encrypted under a password chosen at export (generate button
offered), so a second Mac is import-plus-password, not retyping every credential.

**Team without infra — fifteen minutes once, two minutes per teammate.** One person creates a
free instance on a managed MQTT tier (guide provided), creates one shared username/password,
and types broker address plus credentials into the room dialog once — the only person who
ever sees those fields; the dot turns green. They copy the room invite (one paste-able line
carrying the address, room name, and the broker credential sealed under the room key) and
share it with the room password, which travels out of band like a wifi password. Teammates
paste the invite — during onboarding ("join a team room") or from the ▾ menu — type that one
password, and adopt the room's catalogue on first connect; no file changes hands. *(Revised
2026-08-08, §13.12 — originally the export file was the invitation, which stacked three
passwords onto every joiner.)* Catalogue, schema changes, claims and presence propagate live
within about a second. A closed lid frees that member's claims within a minute or two.
Notify-when-free notifies for real.

**Team with infra — same product, different URL.** Ops runs the shipped compose file
(mosquitto, TLS, password file) on any VM the team can reach; the room address becomes
`mqtts://mqtt.internal.company.com:8883`. Everything else is byte-for-byte persona 2. The
data plane stays on their infrastructure, payload secrets are E2EE on top, and the vendor
operates nothing. Broker migration is repointing one URL; any member reseeds.

### 14.4 Caveat register

**Everyone.** Never on the Mac App Store (sandbox-off is structural, §13.3), and MDM-managed
corporate Macs may need an IT exception for the Accessibility grant. One-tap login is
Simulator-only via `simctl`, the target app must adopt the ten-line handler, and physical
devices fall back to copy/paste. The documented `simctl` argv exposure (§13.2) stands.

**Solo.** The two-Macs problem is resolved 2026-08-07 by encrypted-always exports (§14.5.1).
Backup remains the user's job, now mitigated by local snapshots (§14.5.2). Part of the
product (live claims, presence) stays invisible until a second person exists.

**Team without infra.** Revocation is blunt: rotating the room password is the only way to
remove someone, and it cannot claw back what they already synced. Everyone can edit and
delete everything, names are self-asserted, and there is no history — mitigated by snapshots
(§14.5.2) and a future soft-delete trash, accepted otherwise. LWW can silently drop one side
of a simultaneous same-element edit. The broker operator sees metadata (IPs, display names,
opaque ids, traffic patterns) even though secrets are ciphertext — the encrypt-all-payloads
dial is an open question (§14.7). Free tiers cap connections and promise nothing about
retained durability; reseed covers loss. Presence is a heuristic: flaky wifi can flicker a
claim free, and a crashed Mac holds its claims for a minute or two. A weak room password
weakens the crypto — mitigated by the passphrase generator (§14.5.3).

**Team with infra.** Recorded, resolutions deliberately parked (decision, 2026-08-07):
owning uptime (certs, updates, persistence disk, monitoring, quiet failure modes),
reachability architecture (VPN-bound vs public), broker-hardening foot-guns, residency not
being governance (security teams will still ask for SSO/RBAC/audit — that is §14.6), and
version-skew coordination. Revisit before any self-hosting pilot.

### 14.5 Decisions (2026-08-07)

1. **Exports always include secrets, encrypted.** Exporting requires a password (generate
   button offered); secret values ship as ciphertext in a versioned envelope with the KDF
   salt/params. Import prompts for the password; a skip path imports the catalogue with
   secrets blank. The export/import *blanking* paths are deleted — `mappingSecretValues`
   itself survives, because the persistence placeholder swap and the snapshot writer use
   the same traversal. This retires the solo two-Macs caveat and supersedes the Phase-3
   "include secrets" checkbox plan. *(Amended same day by decision 5: no tolerance for
   older export formats — the version is checked exactly.)*
2. **Periodic local snapshots at `~/.notchboard/snapshots/`** (dot-folder in `$HOME`, the
   dev-tool idiom, like `~/.claude`). Export-format files sealed under a device-local random
   key held in the Keychain, so automatic writes need no password prompt and the folder is
   safe inside any backup. Written periodically and debounced after significant mutations,
   with bounded rotation. This is recovery from sync accidents and mass deletes on *this*
   Mac; cross-machine recovery remains the job of exports, because the device key does not
   travel. Needs an in-app restore flow.
3. **Passphrase generator** on every password field — export now, room create/join when
   rooms land — so "generate" is always one click closer than a weak password.
4. **Persona 3 caveat resolutions parked** — listed in §14.4, decided later.
5. **No compatibility code before first release** (2026-08-07, second decision of the
   day). The app is unpublished with exactly one user, so every migration shim, downgrade
   shadow or legacy-tolerant decode is dead code by definition. Schema and format changes
   reset (state.json's corrupt-backup path) or refuse (exact format-version match on
   imports), never migrate. Version stamps stay in the files, checked but never migrated,
   so real version history can begin at 1.0.
6. **"claim" never appears in user-facing copy.** The UI presents the concept as use:
   "in use by tom", "use + copy", "in use · 12 min ago". Internal identifiers
   (`claimedBy`, `claimOrRelease`, …) keep their names; only labels, toasts, tooltips,
   notifications and settings copy follow the rule.

### 14.6 The backend trigger list (equals the paid tier)

SSO/SCIM, per-user permissions and roles, audit history, removing a leaver without rotating
the room password, one-click hosted rooms, org-wide administration. When two or three real
teams ask for these, that is the signal to build the backend — and the MQTT message schema
is already its API spec. Until then, no server.

### 14.7 Open questions

- ~~Unify the room password and the export password into one per-collection passphrase,
  or keep them separate?~~ **Decided 2026-08-07: separate.** Rotating the room password
  (the only way to remove a leaver) must never invalidate previously shared export
  files, and vice versa. The HKDF info strings differ (`nb-export` / `nb-room`), so even
  an accidentally reused password yields unrelated keys. *(Re-affirmed 2026-08-08 under
  three-passwords pressure, §13.12: merging would make every backup file a room key.
  The fix was routing — each password now appears in exactly one flow — not merging.)*
- ~~Where does the broker account credential live?~~ **Decided 2026-08-08 (§13.12):
  sealed under the room key inside the room config, typed once by the host, travelling
  in invites and exports as ciphertext. Not in each member's Keychain — that made every
  joiner retype a credential that is team-shared by definition.
- ~~Should *all* payloads be encrypted, not just secret fields?~~ **Split answer, both
  decided 2026-08-07.** For *files*, the §13.9 review stands: secrets-only, readable
  catalogue, revisit on a real client's data or a security review. For the *room*, the
  answer is the opposite: every payload is sealed under the room key — a file is read
  once by someone you sent it to, a broker operator watches the whole catalogue stream
  past continuously. The broker sees topic structure, sizes and timing, nothing else.
  Lost mosquitto_sub debuggability is compensated by the local `sync` log category.
- Snapshot cadence and retention numbers.
- Is the WebSocket-443 transport a fallback or the default? (Implemented as a fallback —
  `wss://` addresses work today; untested against a real corp proxy.)
- Passphrase format (word-list vs random characters).
