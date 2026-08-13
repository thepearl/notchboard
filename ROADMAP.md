# Roadmap

What is done, what is next, what is deliberately not happening. Priorities move with what people
actually hit, so an [issue](https://github.com/thepearl/notchboard/issues) is the fastest way to
change this page.

The long form lives in [vision.md](vision.md). Section 13 is the running implementation log,
section 14 is the sync design and its caveat register.

## Where it is now

The docking shell, the catalogue, and the team room all work. Multiple collections, editable group
schemas with typed fields, environments per element, in-use marks with automatic release, the
`simctl` deeplink bridge, encrypted exports, encrypted local snapshots, and end-to-end-encrypted
rooms over MQTT joined with one pasted invite and one password.

The room has passed a two-human test over a public broker on TLS. CI builds and tests every push to
master and every pull request against it.

## Next

**A download that opens on a double click.** Today the only way to get the app is to build it.
A downloaded copy that is not notarised is refused by macOS with a message that reads like a corrupt
file rather than a policy decision. Fixing that needs a Developer ID certificate and Apple's
notarisation service. The full reasoning and the exact steps are in
[docs/RELEASING.md](docs/RELEASING.md).

**A Homebrew cask.** [Casks/notchboard.rb](Casks/notchboard.rb) is written and waiting on the
release above. It installs from a personal tap. A bare `brew install notchboard` needs acceptance
into homebrew-cask, which has notability criteria this project does not meet yet.

**A soft-delete trash.** Deletions are permanent and propagate to the room immediately. Snapshots
cover the accident, but a restore brings back a whole collection rather than one row.

**Burning down the lint.** SwiftLint reports 442 advisory violations, mostly line length and force
unwrapping. CI keeps them non-blocking until they are gone.

## Known limits, accepted for now

These are documented rather than hidden, and each one has a cost that has been weighed.

Revocation is blunt. Removing someone from a room means picking a new room name and a new password,
then reinviting everyone else. There is no server, so there is nobody to revoke them at, and it
cannot claw back what they already synced.

Everyone in a room can edit and delete everything. There are no roles, no per-group permissions, and
no history. Names are self-asserted.

Last-writer-wins can silently drop one side of a genuinely simultaneous edit to the same element.
The escalation, if this starts biting, is a CRDT library rather than a smarter merge.

Presence is a heuristic. Flaky wifi can flicker an in-use mark free, and a Mac that crashes holds its
marks for a minute or two, until the broker publishes its last will. That only changes how the marks
render, though. Nothing releases another Mac's mark, so it returns when that Mac reconnects, and the
automatic release only ever touches your own.

The broker operator sees metadata. Payloads are ciphertext, but room names, group slugs, element and
member ids, counts and traffic timing are not. On a public broker, so does everyone else.

Leaving a room cleans nothing up on the broker. The retained ciphertext stays there, and there is no
purge command.

A wrong room password against an empty room is not detected. Nothing fails, the catalogue is seeded
under a key nobody else shares, and the room quietly forks. A mistyped room name does the same thing,
because nothing provisions a room in the first place.

Broker-side tombstones expire after 30 days. A peer that was offline longer than that can resurrect
a deleted row.

Snapshots do not travel between Macs. Their sealing key is device-local by design. Moving a
collection means exporting it.

## What would need a backend

There is no server today and none is planned on spec. The list that would justify one is short and
specific: SSO and SCIM, per-user permissions and roles, audit history, removing a leaver without
rotating the room password, one-click hosted rooms, and org-wide administration.

When two or three real teams ask for these, that is the signal. Until then the MQTT message schema
is already the API spec, so the work is not wasted.

## Not planned

No Android or emulator support. The docking mechanic reads Simulator.app's window frame and the
login bridge is `xcrun simctl`, so both ends are iOS-specific.

No deep simulator automation. Notchboard fires one deeplink. Seeding fixtures, resetting device
state and scripting multi-step flows are a different tool's job.

No Mac App Store. The App Sandbox has to be off for the Accessibility calls that make docking work,
and a sandboxed process's calls against another process are silently swallowed with no error and no
permission dialog. That is structural, not a setting waiting to be flipped.

No password manager ambitions. This holds shared test credentials for a team, which is a different
threat model from your personal secrets.
