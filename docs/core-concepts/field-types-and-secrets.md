---
icon: lock
description: Seven field types, and what marking one secret actually does.
---

# Field types and secrets

Every field in a group's schema carries a type. The type decides which control the form renders, what passes validation, and for one type, where the value is stored.

## The seven types

| Type     | Accepts                                                                             | Form control                                                                    |
| -------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `text`   | Anything                                                                            | Plain text field                                                                |
| `secret` | Anything                                                                            | Plain text field. The value is masked in the detail view, not while you type it |
| `number` | Anything that parses as a number                                                    | Text field filtered to digits, one leading minus and one decimal point          |
| `bool`   | `true` or `false`                                                                   | Toggle                                                                          |
| `date`   | `YYYY-MM-DD`, parsed with a fixed POSIX format                                      | Text field                                                                      |
| `url`    | Needs a scheme and a host, so `https://api.acme.dev` passes and `acme.dev` does not | Text field                                                                      |
| `picker` | One of the group's declared options                                                 | Menu                                                                            |

An empty value is always valid. It means "not filled in yet", not "wrong".

Validation runs at save time as well as in the form, because values also arrive through imports and hand-edited files where no control can constrain them.

## What `secret` actually does

This is the single most useful thing to know about the app.

Marking a field `secret` is not cosmetic masking. It moves that field's values out of every plaintext surface.

{% hint style="success" %}
The rule is short. If it should not sit in a plaintext file, type it `secret`.
{% endhint %}

### On disk

`state.json` stores a placeholder, never the value. The real value lives in the macOS Keychain under service `flourix.notchboard.secrets`, keyed `<elementID>.<fieldKey>`.

There is one deliberate exception. If a Keychain write fails, because the keychain is locked or the write was denied, the value stays in `state.json` rather than being replaced by a placeholder pointing at nothing. Losing a secret to a transient failure would be worse.

### In an export file

The value travels inside an AES-GCM envelope, sealed under the export password. Every other field is readable plaintext in that file.

### On screen

The detail view shows ten bullets with a reveal and hide toggle per field. The mask is a fixed length on purpose, because a mask sized to its value leaks the length.

Nothing else in the app renders a secret-typed value. That matters most in the list, where a row's subtitle comes from the group's first field. A group whose first field is a secret would otherwise print it in cleartext on every row.

### On the clipboard

Copying a secret marks the clipboard entry as concealed, so cooperating clipboard managers skip it, and clears it after 60 seconds unless you have copied something else since.

### In search

Search deliberately excludes secret-typed values.

Two reasons. With the subtitle masked, a match on a password produced a row with nothing on screen containing the query. And a field that confirms substrings of a secret is a guessing oracle on a panel that sits open beside a shared simulator.

## Changing a field's type

Changing a field away from `secret` drops its value and its Keychain entry. Blanking a secret deletes the entry. Orphaned entries are swept at launch.

{% hint style="warning" %}
That drop is immediate and there is no undo beyond a snapshot. If you are unsure, export the collection first.
{% endhint %}

## What's next?

{% content-ref url="environments.md" %}
[environments.md](environments.md)
{% endcontent-ref %}
