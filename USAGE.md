# Using Notchboard

Notchboard docks a catalogue of test accounts and fixtures to the iOS Simulator window, so
you stop hunting for a working login in chat. This guide walks the whole app. For getting it
built and running, see [INSTALL.md](INSTALL.md).

The app has no Dock icon. Its two entry points are the menu-bar item and the panel itself.

---

## 1. The panel

Notchboard has three shapes.

The notch is a 36×62 tab glued to the edge of the Simulator window. It shows two things: a
square connection dot (amber when the collection is local, green when its team room is live,
red when the room is unreachable) and an arrow pointing away from the Simulator window, `»`
docked right and `«` docked left. Click anywhere on it to expand.

The panel is 404×592 and opens on the same edge. The double-chevron button at the top right
collapses it back to the notch. Which edge it docks to is a setting (Settings → Dock to).

The undocked panel is the same panel, floating on its own. Use it when Simulator is not
running, or when Accessibility permission is unavailable. Menu bar → Show Panel (Undocked).
This outranks docking, so it stays put until you turn it off again.

### Following the Simulator

Notchboard polls the Simulator window position through the Accessibility API and repositions
itself as you drag. Polling is adaptive: roughly 60 Hz while a drag is possible, 10 Hz while
Simulator is merely frontmost, about 3 Hz otherwise.

The docked panel floats above other windows only while Simulator or Notchboard itself is
frontmost. Switch to Chrome and the panel drops behind it, exactly as the Simulator window
does. This is deliberate, and Xcode is deliberately not on that list. The undocked panel and
onboarding keep floating either way, since neither is glued to a window.

### Keyboard shortcuts

Two global chords, defaulting to Control:

| Chord | What it does |
| --- | --- |
| ⌃K | Expand the panel, show the list, focus the search field |
| ⌃N | Expand the panel, open the add-element form |
| ⌘, | Open Settings (inside the panel only) |

Global here is literal: the chord is registered system-wide through Carbon and consumed, so
the frontmost app never sees the keystroke. The catch is that a chord taken this way is taken
system-wide, so Notchboard scopes it twice. It holds the chords only while the panel can
actually respond, and only while Xcode, Simulator or Notchboard is frontmost. Switch to
Terminal and ⌃K is `kill-line` again on the next tick.

That scoping is why Control is a defensible default despite ⌃K and ⌃N being real bindings
elsewhere (Cocoa's delete-to-end-of-paragraph and move-down, zsh's `kill-line` and
`down-line-or-history`). If the collision still bothers you, Settings → Global shortcut offers
⌘ (⌘K / ⌘N) and ⌥⌘ (⌥⌘K / ⌥⌘N). The change takes effect immediately.

Inside the panel, the plain ⌘ chords always work as well, whatever the global modifier is set
to. Panel copy shows whichever modifier you configured, so the list footer and the search
placeholder never lie.

In the list, ↑ and ↓ move the keyboard selection (an amber outline on the row) and Return
opens that element.

---

## 2. The catalogue model

Four levels, and they nest:

A collection is one whole catalogue with its own name, groups, deeplink scheme and optional
team room. The app holds several, Postman-style, and the panel shows one at a time.

A group is a table with a schema. "users", "promos", "products" are groups. It defines an
ordered list of fields, each with a label and a type.

A field is one column of the schema. It has a label, a type, and (for pickers) a list of
options. Fields are edited from the group editor, the ✎ button beside the group tabs. Drag the
⋮⋮ handle to reorder them. Renaming or retyping a field keeps existing values, because fields
are identified by a stable id, not by their label.

An element is one row. It holds a value per field, a name, a note, a set of environments, a
favourite star and (when someone is using it) an in-use mark.

The first field in a group's schema is the primary field. It is what the row's copy button and
the detail view's "use + copy" button put on the clipboard.

### Field types

| Type | Accepts | Form control |
| --- | --- | --- |
| `text` | anything | plain text field |
| `secret` | anything | plain text field (the value is masked in the detail view, not while you type it) |
| `number` | anything that parses as a number | text field filtered to digits, one leading minus and one decimal point |
| `bool` | `true` or `false` | toggle |
| `date` | `YYYY-MM-DD`, parsed with a fixed POSIX format | text field |
| `url` | needs a scheme and a host, so `https://api.acme.dev` passes and `acme.dev` does not | text field |
| `picker` | one of the group's declared options | menu |

An empty value is always valid. It means "not filled in yet", not "wrong". Validation runs at
save time as well as in the form, because values also arrive through imports and hand-edited
files where no control can constrain them.

### What `secret` actually does

This is the single most useful thing to know about the app.

Marking a field `secret` is not cosmetic masking. It moves that field's values out of every
plaintext surface:

- `state.json` on disk stores a placeholder, never the value. The real value lives in the
  macOS Keychain under service `flourix.notchboard.secrets`, keyed `<elementID>.<fieldKey>`.
- An export file carries the value inside an AES-GCM envelope, sealed under the export
  password. Every other field is readable plaintext in that file.
- The detail view shows `••••••••••` with a reveal / hide toggle per field.
- Copying a secret marks the clipboard entry as concealed (cooperating clipboard managers
  skip it) and clears it after 60 seconds, unless you have copied something else since.

Changing a field away from `secret` drops its value and its Keychain entry. Blanking a secret
deletes the entry. Orphaned entries are swept at launch.

The consequence is simple. If it should not sit in a plaintext file, type it `secret`.

---

## 3. Environments

An element carries a set of environments, not one. `DEV`, `STG`, `PRD`, in that display order.

The reason is that the same test account usually exists in more than one place, seeded into
dev and staging with identical credentials. Forcing a single choice made people duplicate the
row, and then one copy drifted.

The chips at the top of the list filter by environment. `ALL` is a filter only, never
assignable to an element.

If you tick `PRD` alongside anything else, Notchboard asks once, at save time, whether you
meant it. A production credential reachable from a dev build is how production data ends up in
a staging log. The dialog has a "Never show this warning again" checkbox, and the same switch
lives in Settings as "Warn before mixing production with another environment".

---

## 4. Using an element

Open an element and press "use + copy". Two things happen: the element is marked in use by
you, and its primary field goes to the clipboard.

The row then shows a green badge with your name on it. Hover the badge for a popover with the
age and the environments. On your own marks it also shows how many idle minutes remain before
auto-release. On someone else's it offers a "notify when free" button, as long as the
catalogue knows about somebody else at all.

The same button on your own element reads "release".

### What teammates see

Without a team room, nobody sees anything: the mark is local. With a room joined, the mark
travels live, attributed to your onboarding name.

Someone else's mark shows their name on the badge and the detail button reads "in use by
<name>". Clicking it does not take the element. Taking someone's element out from under them
should not be a single misclick, so the explicit path is "take over from <name>" in the detail
view.

If the holder is offline (their Mac is asleep, they quit the app, they left the network), the
mark renders free and the button reads "use + copy (<name> offline)". The underlying mark is
untouched and comes back when they do. This is a rendering rule only, never a mutation.

### Auto-release

Your own marks are released automatically after an idle window, 60 minutes by default.
Settings → "Auto-release in-use elements after N min idle", adjustable from 5 to 240 in steps
of 5. The sweep runs every 30 seconds across all collections, not only the visible one.

Only your own marks are swept. Someone else's mark ages on their Mac, and sweeping it here
would be meaningless churn.

### Notify when free

"notify me when it's free" arms a watch on an element held by someone else. When it is
released (manually, by auto-release, or because the holder went offline) you get a macOS
notification.

The watch is in-memory and does not survive a relaunch. Permission is requested at the first
click that needs it, never at launch. Settings has a toggle for whether the notification plays
a sound.

### Copy actions

- The copy button on a row copies the primary field.
- "use + copy" in the detail view copies the primary field and marks the element.
- "copy password" copies the group's first `secret` field on its own and leaves the mark
  alone. It only appears when that field actually holds a value. Use it with the button
  beside it and you have the two values in the order a login form wants them.
- Each field row in the detail view is itself a copy button, with an explicit copy icon.

---

## 5. The deeplink bridge

"login on sim" fires a URL into the booted simulator so your app logs itself in.

It runs:

```bash
xcrun simctl openurl booted "<scheme>://debug/login?user=…&pass=…"
```

The username comes from the element's `username` field. The password comes from the group's
first `secret` field, read from memory, so the real value and not the on-disk placeholder.
Both are percent-encoded aggressively (against alphanumerics only), so an email's `@` and `+`
and every punctuation character a generated password can carry survive the trip. If the
element has no `username` value the button is not shown. If the group has no secret field, or
that field is empty on this element, the URL carries only `user=`.

### Setting the scheme

The scheme is per collection, because each catalogue describes one app. Two places to set it:

- The ▾ menu next to the collection name in the panel header. The item reads "set deeplink
  scheme" while there is none, and "deeplink scheme: <scheme>://…" once one is set.
- Settings → Simulator deeplink → Debug URL scheme.

`mythos`, `mythos:`, `mythos.` and `mythos://` all normalise to `mythos`. Network schemes
(`http`, `https`, `ftp`, `file`, `ws`, `wss`) are refused, so pasting your app's universal link
can never fire credentials at a live host as query parameters.

### What the app under test needs

Two pieces, and nothing else. Register the scheme in the debug build's `Info.plist`, and handle
the route:

```swift
.onOpenURL { url in
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          components.host == "debug", components.path == "/login",
          let user = components.queryItems?.first(where: { $0.name == "user" })?.value
    else { return }
    let pass = components.queryItems?.first(where: { $0.name == "pass" })?.value
    // fill your login form and submit
}
```

`SampleApp/README.md` in this repo is the working reference integration, with the full
`Info.plist` block and a runnable demo app. Two things it documents that are worth knowing
before you assume the bridge is broken: iOS raises an "Open in <app>?" confirmation the first
time a custom scheme is fired from outside, once per simulator install and not once per login.
And re-firing while already signed in swaps accounts, if your handler resets the session first.

If the deeplink succeeds and the element was free, it is marked in use automatically. Logging
in as an account is using it. If `simctl` fails, nothing is marked.

### When to use "copy password" instead

Some logins a deeplink cannot drive. SSO redirects, Okta, anything rendered in a WebView, any
flow where your app never receives the URL. For those, use "use + copy" for the username and
"copy password" for the password, then paste them by hand. You still get the in-use mark, so
teammates still see the account is taken.

### One accepted exposure

`simctl` takes the URL as a command-line argument, so while that short-lived process runs the
password is readable in the process list by other processes running as you. There is no
argv-free way to hand `simctl` a URL. These are shared test credentials on a local dev tool,
so the trade-off is accepted and documented rather than hidden. Everything under Notchboard's
own control (its log lines, and `simctl`'s echoed stderr) is redacted. See the header of
`notchboard/Docking/SimctlBridge.swift`.

---

## 6. Collections

The ▾ menu next to the collection name in the panel header is the collection manager.

Switching lists every collection with a tick beside the active one.

New creates an empty collection with a single "users" group.

Rename renames the catalogue. With a room joined, the new name travels.

Duplicate copies the active collection, appending " copy" to the name. Every element in the
copy gets a fresh id, so the copy's secrets land under their own Keychain entries instead of
aliasing the original's.

Delete is disabled when there is only one collection, and purges that collection's Keychain
secrets.

### Exporting

Menu bar → Export Collection. Choose a destination, then set a file password. The password is
mandatory, and the prompt has a Generate button that produces a passphrase like
`kw3ph-x87mn-qv2tc-e9rju`. The field shows the password in the clear on purpose, because a
passphrase you cannot read is one you cannot share.

What is encrypted in a `.notchboard` file:

- every `secret`-typed field value, sealed into one AES-GCM envelope under the file password
- the broker account password, if the collection has a room. That one is sealed under the room
  key, not the file password, and it travels already sealed.

What is plaintext and readable by anyone who opens the file:

- element names, notes and `lastUsed` strings
- every field value that is not `secret`-typed, usernames included
- the group schemas, field labels and types
- environments
- the collection name
- the room address and room name, if the collection has one

That split is a reviewed choice. Being able to open a collection file in a text editor and read
what is in it is worth real debuggability. The per-field lever is the field type: mark a field
`secret` and it moves into the encrypted envelope.

In-use marks are always stripped on export. A mark frozen into a file arrives stale by
construction.

The room password never travels in a file.

### Importing

Menu bar → Import Collections, or double-click a `.notchboard` file in Finder, or use Finder's
"Open With".

Import adds a collection alongside your existing ones. It never replaces anything.

If the file carries secrets you are asked for its file password. A wrong password re-prompts.
"Import Without Secrets" brings in everything else with the secret fields blank, which is a
legitimate way to get a colleague's schema without their credentials.

Secret values only ever enter through the authenticated envelope. Any in-band secret value in
the JSON is force-blanked on import whatever the file says, so a hand-crafted file cannot
smuggle values in.

A file exported from a different format version is refused, not migrated.

---

## 7. Team rooms

A room is how two or more Macs keep one collection in sync, live. Edits, schema changes,
deletions and in-use marks flow both ways as they happen, with no polling and no refresh.

### There is no Notchboard server

You bring your own MQTT broker. Notchboard has no backend, and the broker only ever relays
ciphertext: every payload is sealed under the room key before it leaves your Mac. The broker
operator sees topic names, message sizes and timing, and nothing else.

Anything that speaks MQTT 5 works. A managed broker (HiveMQ Cloud, EMQX Cloud) or your own
mosquitto both do.

### Broker addresses

Three accepted forms:

| Form | Default port | When |
| --- | --- | --- |
| `mqtts://[user@]host[:8883]` | 8883 | the normal case, TLS over TCP |
| `wss://[user@]host[:443][/path]` | 443 | MQTT over WebSocket and TLS, the corporate-firewall fallback |
| `mqtt://localhost[:1883]` | 1883 | plaintext, loopback only, for a local mosquitto |

Plaintext `mqtt://` to anything other than `localhost`, `127.0.0.1` or `::1` is refused with
"mqtt:// is allowed for localhost only — use mqtts:// for <host>". This is not a bug and there
is no flag to weaken it. Sending credentials over cleartext to a real host is exactly the
mistake the refusal exists to prevent.

A broker username rides inside the URL (`mqtts://team@broker.example:8883`). The broker
password is typed separately in the setup dialog.

### Creating a room

▾ menu → "set up team room". One person does this, once.

Fill in the broker address, a room name (lowercase letters, digits and dashes, e.g.
`acme-mobile`), the broker username and password if your broker needs an account, and a room
password. Generate is beside the room password field.

Copy the room password now. It goes straight to the Keychain and is never displayed again.

The room name is one room per collection. It namespaces your topics on the broker, so pick
something specific to your team.

### The room password is the only key

Everything published to the room is AES-GCM ciphertext under a key derived from the room
password (PBKDF2, then HKDF domain-separated with `nb-room`, salted deterministically from
broker host plus room name so every member derives the same key with no handshake).

Consequences worth knowing:

- Anyone with the room password can read the room. Anyone without it can read nothing, the
  broker operator included.
- Removing someone from the room means moving to a new room name. Rotating the password in
  place is refused by the dialog, because everything the broker holds is retained ciphertext
  under the old key and nothing purges it. You would lock out the whole team, yourself
  included. The dialog tells you to pick a new room name instead.
- A wrong room password is detected before anything is applied, and never applies plausible
  garbage to your catalogue.

The room password is stored in the Keychain under service `flourix.notchboard.rooms`. It is
shared out of band, like a wifi password.

### The invite

▾ menu → "copy room invite". This puts one line on your clipboard:

```
notchboard-room:eyJicm9rZXJVUkwiOi…
```

It is base64url of the room config. What is inside and readable by anyone who gets the line:
the broker address, the broker username, and the room name. What is inside and not readable:
the broker account password, sealed under the room key.

What is not inside at all: the room password.

So the invite line plus the room password is everything a teammate needs, and the invite on
its own gives away only where the room is, not what is in it. Send them separately.

The invite is a paste-code rather than a clickable URL on purpose. It needs no LaunchServices
registration, survives being sent through chat or email, and cannot be triggered by a stray
click.

### Joining

Three doors, all the same flow: paste the invite, type the room password.

- ▾ menu → "join with an invite"
- Menu bar → Join Room with Invite
- Onboarding → "join a team room" as your starting point

On first connect, if the room already holds a catalogue, it replaces this collection's
contents. Your local copy is snapshotted first, so a mis-join is reversible. If the room is
empty, your local catalogue seeds it.

An imported `.notchboard` file that carries a room address triggers a join prompt on import,
and that prompt asks for the room password only, never the broker credential. "Not Now" keeps
the address on the collection, so joining later is the room item in the ▾ menu, which reopens
the room dialog with the address already filled in.

### What syncs and what does not

Syncs: element content (name, values including secrets, note, environments, `lastUsed`), group
schemas and their order, the collection name, deletions, and in-use marks.

Does not sync, deliberately:

- Favourites. Starring a row is personal, and it never bumps the element's timestamp either,
  so it cannot beat a teammate's real edit.
- The notify-when-free watch list. Also personal, and in-memory only.
- Your deeplink scheme and every setting in Settings.
- Snapshots.

Conflicts resolve last-write-wins on the element, with the member id breaking exact ties
deterministically on every Mac.

### Presence

Once connected, the panel header shows "· N online", counting you. The list footer carries the
same count on the right, where the shortcut hint sits when there is no room. On the left it
shows how many elements are in use, then the connection word: local / connecting… / live /
room offline / room unreachable.

The connection dot is the amber square beside the "notchboard" wordmark, and the same dot on
the notch when collapsed. Amber means local or connecting, green means live, red means the
room is unreachable. It never animates.

An offline member's in-use marks render free, so a colleague who shut their laptop does not
leave rows locked. Their mark is untouched and returns when they do. Closing the lid publishes
a proper goodbye, so presence flips within a second or two rather than waiting out the 45
second keepalive.

Reconnection is automatic with exponential backoff from 1 to 60 seconds. You keep working
locally the whole time, and everything you changed while offline is pushed on reconnect.

### Leaving

▾ menu → "leave room", or Settings → Team room → Leave Room.

The collection keeps everything it has and stops sending and receiving. The room password is
deleted from this Mac's Keychain, so rejoining means pasting the invite and the password
again.

### Honest rough edges

Documented rather than hidden:

- A mark you released while offline is reinstated by its own retained copy on reconnect, and
  then ages out through the auto-release sweep. A mark is a status light, and a minute of
  staleness beat adding a special case to the protocol.
- Deletion records expire after 30 days on the broker. A Mac that was offline longer than that
  can resurrect a deleted row.
- Two people editing the same element within the same instant means one edit is silently
  dropped. Last-write-wins is the accepted trade here.
- Restoring a snapshot does not tear down sessions for collections the restore removed. They
  go on the next relaunch. Deleting a collection handles it properly.

---

## 8. Snapshots

Notchboard writes an encrypted snapshot of every collection to `~/.notchboard/snapshots/`,
one file per snapshot, named like `notchboard-20260811-142530.nbsnap`.

They are taken on successful saves, rate-limited to at most one per 15 minutes, and rotated at
24 files. A snapshot is also forced, ignoring the interval, before two destructive moments:
adopting a room's catalogue on first connect, and restoring a snapshot.

Each file is one AES-GCM box sealed under a random key held in the Keychain under service
`flourix.notchboard.device`. That makes the folder safe to include in a backup.

To restore: menu bar → Restore Snapshot, pick a file, confirm. This replaces all collections,
not just the active one, because a snapshot is a consistent moment in time. A fresh snapshot
of the current state is taken first, so a mis-restore is itself reversible.

The sealing key is device-local and never leaves the Mac, so snapshots do not travel. Copying
the folder to another machine gives you files nothing can open. Cross-machine recovery is what
encrypted exports are for.

---

## 9. Settings

Menu bar → Settings, or ⌘, from the panel.

Behaviour:

- Start expanded when docking. Whether the panel opens as a panel or as a notch.
- Dock to. Left or right edge of the Simulator window. The notch and the coach mark mirror
  with it.
- Auto-release in-use elements after N min idle. 5 to 240, in steps of 5, default 60.
- Global shortcut. ⌃ Control, ⌘ Command or ⌥⌘ Option-Command for the K and N chords. Takes
  effect immediately.
- Play a sound with notifications. Applies to notify-when-free.
- Launch at login. If macOS puts the registration in a pending state, a "Pending your approval
  in Login Items" row appears with a button that opens the right System Settings pane.

Simulator deeplink, scoped to the active collection:

- Debug URL scheme. The scheme "login on sim" fires into. One per collection.
- Warn before mixing production with another environment. Asked once, when you save.

Team room, scoped to the active collection:

- With a room: its name and broker host, the connection status with the online count, and a
  Leave Room button.
- Without one: "Local — no team room." and a Join with an Invite button.

At the bottom, Replay Onboarding restarts the first-run flow. It asks for confirmation first,
because finishing onboarding replaces the active collection.

---

## Where your data lives

| Path | What |
| --- | --- |
| `~/Library/Application Support/Notchboard/state.json` | collections, settings, your member id. Secret values are Keychain placeholders here, never real values |
| `~/Library/Application Support/Notchboard/state.json.corrupt` | a previous state file that could not be read, kept rather than discarded |
| `~/.notchboard/snapshots/` | encrypted snapshots, `.nbsnap` |

Keychain services:

| Service | Holds |
| --- | --- |
| `flourix.notchboard.secrets` | `secret`-typed field values, keyed `<elementID>.<fieldKey>` |
| `flourix.notchboard.rooms` | room passwords, one per broker and room |
| `flourix.notchboard.device` | the device-local snapshot sealing key |

Delete `state.json` to simulate a first launch. If Notchboard cannot read it, it moves the file
aside and tells you so in an alert rather than silently starting over.

A collection moved to another Mac through `state.json` alone will load with its secret fields
empty, because the Keychain does not come with it. Use an encrypted export, or a room.
