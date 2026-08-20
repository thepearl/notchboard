---
icon: box-archive
description: Move a collection between Macs, and get one back after an accident.
---

# Exports, imports and snapshots

Two separate mechanisms, easily confused. An export is a file you send to someone. A snapshot is a local safety net that never leaves your Mac.

## Exporting a collection

Menu bar → **Export Collection**. Choose a destination, then set a file password.

The password is mandatory, and the prompt has a Generate button that produces a passphrase like `kw3ph-x87mn-qv2tc-e9rju`. The field shows the password in the clear on purpose, because a passphrase you cannot read is one you cannot share.

{% tabs %}
{% tab title="Encrypted" %}
* Every secret-typed field value, sealed into one AES-GCM envelope under the file password.
* The broker account password, if the collection has a room. That one is sealed under the room key rather than the file password, and it travels already sealed.
{% endtab %}

{% tab title="Plaintext" %}
Readable by anyone who opens the file in a text editor:

* Element names, notes and last-used stamps.
* Every field value that is not secret-typed, usernames included.
* The group schemas, field labels and types.
* Environments.
* The collection name.
* The room address and room name, if the collection has one.
* The member list mapping member ids to display names.
{% endtab %}
{% endtabs %}

That split is a reviewed choice. Being able to open a collection file and read what is in it is worth real debuggability. The per-field lever is the field type.

In-use marks are always stripped on export, because a mark frozen into a file arrives stale by construction. Names are not stripped, so strip them by hand if you are sending a catalogue outside the team.

The room password never travels in a file.

{% hint style="info" %}
A file is exactly as strong as the password you gave it. Use the generator.
{% endhint %}

## Importing

Menu bar → **Import Collections**, or double-click a `.notchboard` file in Finder, or use Finder's Open With.

Import adds a collection alongside your existing ones. It never replaces anything.

If the file carries secrets you are asked for its file password, and a wrong password re-prompts. **Import Without Secrets** brings in everything else with the secret fields blank, which is a legitimate way to get a colleague's schema without their credentials.

{% hint style="success" %}
Secret values only ever enter through the authenticated envelope. Any in-band secret value in the JSON is force-blanked on import whatever the file says, so a hand-crafted file cannot smuggle values in.
{% endhint %}

A file exported from a different format version is refused, not migrated.

An imported file that carries a room address triggers a join prompt, and that prompt asks for the room password only, never the broker credential. **Not Now** keeps the address on the collection, so joining later reopens the room dialog with the address already filled in.

## Snapshots

Notchboard writes an encrypted snapshot of every collection to `~/.notchboard/snapshots/`, one file per snapshot, named like `notchboard-20260811-142530.nbsnap`.

They are taken on successful saves, rate-limited to at most one per 15 minutes, and rotated at 24 files. A snapshot is also forced, ignoring the interval, before two destructive moments: adopting a room's catalogue on first connect, and restoring a snapshot.

Each file is one AES-GCM box sealed under a random key held in the Keychain under service `flourix.notchboard.device`. That makes the folder safe to include in a backup.

### Restoring

Menu bar → **Restore Snapshot**, pick a file, confirm.

This replaces all collections, not just the active one, because a snapshot is a consistent moment in time. A fresh snapshot of the current state is taken first, so a mis-restore is itself reversible.

{% hint style="warning" %}
The sealing key is device-local and never leaves the Mac, so snapshots do not travel. Copying the folder to another machine gives you files nothing can open. Cross-machine recovery is what encrypted exports are for.
{% endhint %}

## Moving a collection to another Mac

Export it. The export password restores the secrets on the other side.

Copying `state.json` alone leaves secret fields empty, because the Keychain entries stay behind on the original machine.
