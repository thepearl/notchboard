# Notchboard [![CI](https://github.com/thepearl/notchboard/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/thepearl/notchboard/actions/workflows/ci.yml)

A macOS menu-bar app that docks a shared catalogue of test accounts and fixtures to the iOS
Simulator window.

Every mobile team keeps its working logins somewhere bad. A pinned Slack message, a Notion page
nobody updates, a note on someone's second monitor. You lose a minute finding the staging account,
another minute discovering a teammate is already logged into it, and you retype the password by
hand into the simulator.

Notchboard puts that catalogue next to the simulator you are already looking at. It attaches a slim
notch to the edge of the Simulator window and follows it as the window moves. Click the notch and
the list opens: search, pick an account, copy it or fire it straight into the booted app as a
deeplink. Mark it "in use" and the rest of the team sees it is taken.

There is no backend. The app is local-first, and teams that want live sharing join an
end-to-end-encrypted room on any standard MQTT broker.

## What it does

- Multiple collections, Postman style, each with its own groups, schemas and settings.
- Groups with editable field schemas, and elements with typed fields (text, secret, number, url,
  date, bool, picker).
- Environments per element (`DEV`, `STG`, `PRD`, and an element can sit in more than one),
  favourites, search and keyboard navigation.
- Marking an element "in use", which teammates in the same room see, with automatic release after
  an idle window you set (5 to 240 minutes, 60 by default).
- A deeplink bridge that fires `<scheme>://debug/login?...` into the booted simulator through
  `xcrun simctl openurl`, plus a plain copy button for logins a deeplink cannot drive (SSO or
  WebView screens).
- Encrypted `.notchboard` export files, and encrypted local snapshots with restore from the menu
  bar.
- Optional end-to-end-encrypted team rooms over MQTT, joined with one pasted invite line and one
  room password.
- Global shortcuts, ⌃K to open the panel with the search field focused and ⌃N to add an element.
  They only fire while Xcode, Simulator or Notchboard is frontmost, and the modifier is a setting
  (⌃, ⌘ or ⌥⌘).

## Requirements

- macOS 14.0 or later.
- Xcode to build. There is no prebuilt download yet, so building from source is the only way to get
  the app today. [INSTALL.md](INSTALL.md) explains why, and which Xcode version the project needs.
- Simulator.app running for the docked presentation, and a booted simulator for the deeplink
  bridge. Without either, the panel is still usable, undocked, from the menu bar.
- Accessibility permission granted to the app in System Settings, Privacy and Security,
  Accessibility. Reading another app's window frame is exactly what that permission gates, so
  docking cannot work without it.

The app is not notarised and is not on the App Store. A copy you built yourself is not quarantined,
so Gatekeeper does not block it.

## Quick start

```bash
git clone https://github.com/thepearl/notchboard.git
```

Open `notchboard.xcodeproj` and run. A fresh clone builds with no Apple developer account and no
team, because signing is ad-hoc and the development team is left empty.

Full instructions, including where the built app lands and how to grant Accessibility, are in
[INSTALL.md](INSTALL.md). Day-to-day use is in [USAGE.md](USAGE.md).

## How docking works

Notchboard runs as an agent, so it has no Dock icon and never takes focus away from Simulator or
Xcode. Its panel is a borderless non-activating window, which is why you can type in its search
field while Simulator stays frontmost.

To dock, the app polls the Accessibility API for Simulator's real window frame and repositions
itself against it, faster while you are dragging the window and slower when nothing is moving.
That is the only thing the Accessibility permission is used for. If the permission is missing or
Simulator is not running, the menu bar still opens the panel as a normal floating window, and
onboarding has a "continue without docking" path for Macs where the permission toggle will not
stick.

## Team rooms

A collection can join a room on any standard MQTT broker. Peers exchange sealed messages through
it, so edits, new elements and in-use marks propagate to everyone else's Mac as they happen. The
broker holds retained messages, which is how someone who joins later gets the whole catalogue with
no history protocol of our own.

Joining is one pasted invite line plus one room password. The host picks "copy room invite" from
the collection menu in the panel header, sends the line however they like, and shares the room
password separately.
[USAGE.md](USAGE.md) walks through hosting and joining, including which brokers work.

## Security and privacy

Read this before putting anything sensitive into a room or an export file.

Every room payload is sealed with AES-GCM under a key derived from the room password (PBKDF2, then
HKDF with a room-specific salt). The broker relays bytes it cannot read. Send the wrong room
password and messages fail to open cleanly rather than being applied as garbage.

The room password is the entire security boundary. It is shared out of band, like a wifi password,
and never travels in an invite or an export file. The dialog that creates a room puts a "Generate"
button next to the password field, and so does the export password prompt. Using it is a good idea.

Topic names are not encrypted. A broker operator sees the room name, your group names (a topic path
carries the group's slug), how many members are connected, and the shape and timing of the traffic.
On a public broker, so does everyone else. Pick a room name that gives nothing away, and prefer a
broker you control.

An export file protects secret-typed values only. Element names, usernames, notes, schemas and
environments are readable plaintext in the file. In-use marks are stripped on export, so nobody's
name travels with it. The plaintext is a deliberate trade-off, documented in vision.md 13.9: being
able to open a collection file and read it is worth the debuggability. The per-field lever is the
field type. Mark a field secret and its value moves into the encrypted envelope. A file is exactly
as strong as the password you gave it.

There is one place a password leaves the Keychain in the clear. `simctl` takes the deeplink URL as
a command-line argument, so while that short-lived process runs, a password in the query is
readable by other processes running as you. There is no argv-free way to hand `simctl` a URL.
These are shared test credentials on a local developer tool, so the exposure is accepted and
documented rather than hidden. Everything under the app's control (its own log lines and `simctl`'s
echoed stderr) is redacted. See the header of `notchboard/Docking/SimctlBridge.swift`.

Removing someone from a room means picking a new room name and a new room password, then sending a
fresh invite to everyone else. There is no server, so there is nobody to revoke them at.

## Where your data lives

```
~/Library/Application Support/Notchboard/state.json   collections and settings
~/.notchboard/snapshots/                              encrypted snapshots
```

`state.json` holds no secret values. Secret-typed fields are replaced by placeholders and the real
values live in the login Keychain, under three services:

- `flourix.notchboard.secrets` for secret field values.
- `flourix.notchboard.rooms` for room passwords.
- `flourix.notchboard.device` for the key that seals snapshots, which is why snapshots do not
  travel between Macs.

A `state.json` that cannot be decoded is moved aside to `state.json.corrupt` instead of being
discarded, and the app tells you it happened. Delete the file to simulate a first launch.

To move a collection to another Mac, export it. The export password restores the secrets on the
other side. Copying `state.json` alone leaves secret fields empty, because the Keychain entries
stay behind.

## Licence

Apache-2.0. See [LICENSE](LICENSE).

Third-party components and their licences are listed in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md). The bundled fonts, Space Grotesk and JetBrains
Mono, are under the SIL Open Font License 1.1.

## Design reasoning

[vision.md](vision.md) is the product specification. Section 13 is the running implementation log,
including the things that were tried and abandoned. Section 14 is the sync design.

[CLAUDE.md](CLAUDE.md) is the working document for anyone changing the code. It lists the
constraints that are load-bearing, such as the disabled App Sandbox, the non-activating panel and
the animation budget, none of which are safe to change casually.
