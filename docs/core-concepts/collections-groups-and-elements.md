---
icon: sitemap
description: The four levels of the catalogue, and how to manage the top one.
---

# Collections, groups and elements

Four levels, and they nest.

## Collection

One whole catalogue, with its own name, groups, deeplink scheme and optional team room. The app holds several at once, Postman-style, and the panel shows one at a time.

The ▾ menu next to the collection name in the panel header is the collection manager.

| Action              | What it does                                                                                                                                                                   |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Switch              | Lists every collection with a tick beside the active one                                                                                                                       |
| New collection      | Creates an empty catalogue with a single `users` group, and switches to it                                                                                                     |
| Rename              | Renames the catalogue. With a room joined, the new name travels                                                                                                                |
| Duplicate           | Copies the active collection, appending " copy". Every element gets a fresh id, so the copy's secrets land under their own Keychain entries instead of aliasing the original's |
| Set deeplink scheme | The URL scheme one-click login fires into, stored per collection                                                                                                               |
| Set up team room    | Broker URL, room name, room password                                                                                                                                           |
| Copy room invite    | Puts the one-line invite on the pasteboard. Shown only once a room exists                                                                                                      |
| Join with an invite | The other side of that, shown only when the collection has no room                                                                                                             |
| Leave room          | Keeps everything local and stops sending and receiving                                                                                                                         |
| Delete              | Removes the collection and purges its Keychain secrets. Disabled when it is the last one                                                                                       |

## Group

A table with a schema. `users`, `promos` and `products` are groups.

Group tabs run along the top of the list, each showing its element count. The ✎ button beside them opens the group editor.

## Field

One column of the schema, with a label, a type, and for pickers a list of options.

Fields are edited from the group editor. Drag the ⋮⋮ handle to reorder them. Renaming or retyping a field keeps existing values, because fields are identified by a stable id rather than by their label.

{% hint style="success" %}
The first field in a group's schema is the primary field. It is what the row's copy button and the detail view's **use + copy** button put on the clipboard.
{% endhint %}

## Element

One row. It holds a value per field, a name, a note, a set of environments, a favourite star, and when someone is using it, an in-use mark.

### Using one

Open an element and press **use + copy**. The element is marked in use by you and its primary field goes to the clipboard. The same button on your own element then reads **release**.

The row shows a green badge with your name on it. Hover the badge for a popover with the age and the environments. On your own marks it also shows how many idle minutes remain before auto-release. On someone else's it offers a **notify when free** button.

### Copy actions

* The copy button on a row copies the primary field.
* **use + copy** in the detail view copies the primary field and marks the element.
* **copy password** copies the group's first secret-typed field on its own and leaves the mark alone. It appears only when that field actually holds a value.
* Each field row in the detail view is itself a copy button, with an explicit copy icon.

### Auto-release

Your own marks release automatically after an idle window, 60 minutes by default and adjustable from 5 to 240 in steps of 5. The sweep runs every 30 seconds across all collections, not only the visible one.

Only your own marks are swept. Someone else's mark ages on their Mac, and sweeping it here would be meaningless churn.

### Taking an element someone else holds

Someone else's mark shows their name on the badge and the detail button reads "in use by \<name>". Clicking it does not take the element. The explicit path is **take over from \<name>** in the detail view, because pulling an account out from under a teammate should not be a stray click in a list.

### Favourites and search

A star per row marks a favourite. It is local only and never travels to a room, and it never bumps the element's timestamp either, so it cannot beat a teammate's real edit.

Search is a case-insensitive match over the name, the note and every field value in the active group, with one deliberate exception covered in [field types and secrets](field-types-and-secrets.md).
