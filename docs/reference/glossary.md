---
icon: bookmark
description: Terms you will meet in the app and in these docs.
---

# Glossary

**Collection.** One whole catalogue, with its own name, groups, deeplink scheme and optional team room. The app holds several at once and shows one at a time.

**Group.** A table with a schema, such as `users` or `promos`. Group tabs run along the top of the list.

**Field.** One column of a group's schema, with a label, a type and for pickers a list of options. Identified by a stable id, so renaming keeps existing values.

**Element.** One row in a group. Holds a value per field, a name, a note, a set of environments, a favourite star, and sometimes an in-use mark.

**Primary field.** The first field in a group's schema. It is what the row's copy button and **use + copy** put on the clipboard.

**Secret field.** A field typed `secret`. Its values move out of every plaintext surface, into the Keychain on disk and into an encrypted envelope in an export file. See [field types and secrets](../core-concepts/field-types-and-secrets.md).

**Environment.** `DEV`, `STG` or `PRD`. An element carries a set of them, not one. `ALL` is a filter sentinel and never assignable.

**In-use mark.** The record that someone has taken an element. Shows as a green badge with their name. Releases itself after an idle window, 60 minutes by default. The word `claim` never appears in the interface.

**Notch.** The 36×62 tab glued to the edge of the Simulator window. Click it to expand into the panel.

**Panel.** The 404×592 catalogue window. Docked to the Simulator window by default, or undocked and free-floating.

**Undocked panel.** The same panel, floating on its own. Opened from the menu bar. It outranks docking, and is the fallback when Simulator is not running or Accessibility is unavailable.

**Coach mark.** The one-off pointer that appears beside the notch after setup, the first time the panel docks.

**Team room.** One collection kept in sync across Macs through an MQTT broker, end-to-end encrypted under the room password.

**Room password.** The single key for a room. Derived into an AES-GCM key, stored in the Keychain, shared out of band. It never travels in an invite or an export file.

**Broker.** The MQTT server that relays room traffic. You choose it, and it only ever sees ciphertext.

**Invite.** The one-line `notchboard-room:` paste-code carrying the room config. The broker account password inside it is sealed under the room key. The room password is not in it at all.

**Presence.** Who is online in the room. An offline member's in-use marks render free without being mutated.

**Export.** A password-protected `.notchboard` file. Secret-typed values are encrypted, everything else is readable plaintext.

**Snapshot.** An encrypted local copy of every collection in `~/.notchboard/snapshots/`, sealed under a device-local key. Snapshots do not travel between Macs.

**Deeplink bridge.** The **login on sim** button, which fires `<scheme>://debug/login?user=…&pass=…` into the booted app through `xcrun simctl openurl`.

**Member id.** The persisted local identifier for your Mac, paired with the display name you set during onboarding. It is what attributes an in-use mark to you.
