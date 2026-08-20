---
icon: book
description: How collections, groups, elements and field types fit together.
---

# Core concepts

A few ideas shape everything else in the app. You do not need to memorise them, but skimming them now will save confusion later.

<table data-card-size="large" data-view="cards"><thead><tr><th></th><th></th><th></th><th data-hidden data-card-target data-type="content-ref"></th></tr></thead><tbody><tr><td><h4><i class="fa-sitemap" style="color:$primary;">:sitemap:</i></h4></td><td><strong>Collections, groups and elements</strong></td><td>The four levels of the catalogue, and how they nest.</td><td><a href="collections-groups-and-elements.md">collections-groups-and-elements.md</a></td></tr><tr><td><h4><i class="fa-lock" style="color:$primary;">:lock:</i></h4></td><td><strong>Field types and secrets</strong></td><td>Seven field types, and what marking one <code>secret</code> actually does.</td><td><a href="field-types-and-secrets.md">field-types-and-secrets.md</a></td></tr><tr><td><h4><i class="fa-layer-group" style="color:$primary;">:layer-group:</i></h4></td><td><strong>Environments</strong></td><td>Why an element carries a set of environments rather than one.</td><td><a href="environments.md">environments.md</a></td></tr></tbody></table>

***

### The mental model in 30 seconds

You have one or more **collections**, each one a whole catalogue for a single app or project. A collection holds **groups**, and a group is a table with a schema. That schema is an ordered list of **fields**, each with a label and a type. An **element** is one row, holding a value per field.

Everything is local until you tell a collection to join a **team room**. Then that one collection syncs live with everyone else who has the room password.

That is it. The rest is detail.

### Where things live

| Path                                                          | What is in it                                                                                             |
| ------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `~/Library/Application Support/Notchboard/state.json`         | Collections, settings and your member id. Secret values are Keychain placeholders here, never real values |
| `~/Library/Application Support/Notchboard/state.json.corrupt` | A previous state file that could not be read, kept rather than discarded                                  |
| `~/.notchboard/snapshots/`                                    | Encrypted snapshots, one `.nbsnap` file each                                                              |

Three Keychain services back that up, in the login keychain.

| Service                      | Holds                                                     |
| ---------------------------- | --------------------------------------------------------- |
| `flourix.notchboard.secrets` | Secret-typed field values, keyed `<elementID>.<fieldKey>` |
| `flourix.notchboard.rooms`   | Room passwords, one per broker and room                   |
| `flourix.notchboard.device`  | The device-local key that seals snapshots                 |

{% hint style="info" %}
Delete `state.json` to simulate a first launch. If Notchboard cannot read it, the file is moved aside and you get an alert rather than a silent reset.
{% endhint %}
