---
icon: compass
description: >-
  A guided walkthrough from an empty catalogue to an account you can log into
  with one click.
---

# Your first collection

The panel is built around one loop. Find the account, take it, get into the app. This page walks that loop once, end to end.

## The three shapes of the panel

Notchboard shows up in three forms, and it helps to recognise them before anything else.

* The notch is a 36×62 tab glued to the edge of the Simulator window. It shows a square connection dot and an arrow pointing away from the simulator. Click anywhere on it to expand.
* The panel is 404×592 and opens on the same edge. The double-chevron button at the top right collapses it back.
* The undocked panel is the same panel, floating on its own. Use it when Simulator is not running, or when Accessibility is unavailable. It outranks docking, so it stays put until you turn it off.

{% hint style="info" %}
The docked panel floats above other windows only while Simulator or Notchboard is frontmost. Switch to your browser and it drops behind, exactly as the Simulator window does. That is deliberate, not a bug.
{% endhint %}

## Steps

{% stepper %}
{% step %}
#### Create a group, or use one you have

A group is a table with a schema. The sample catalogue ships with several. A fresh empty catalogue starts with one group called `users`.

Group tabs run along the top of the list, each with its element count. The ✎ button beside them opens the group editor, where you add fields, rename them, retype them and drag the ⋮⋮ handle to reorder.

Renaming or retyping a field keeps existing values, because fields are identified by a stable id rather than by their label.
{% endstep %}

{% step %}
#### Add an element

Press ⌃N anywhere in Xcode, Simulator or Notchboard, and the add-element form opens with the panel.

Pick the group, and its schema decides which fields you get. Fill them in. Validation runs at save rather than as you type, because values also arrive through imports and hand-edited files.

Tick the environments the account exists in. An element carries a set, not one value, because the same test account is usually seeded into dev and staging with identical credentials.

{% hint style="warning" %}
Tick `PRD` alongside anything else and Notchboard asks once, at save, whether you meant it. A production credential reachable from a dev build is how production data ends up in a staging log.
{% endhint %}
{% endstep %}

{% step %}
#### Mark the password as a secret

In the group editor, set the password field's type to `secret`.

This is not cosmetic masking. It moves that field's values out of every plaintext surface: the state file on disk stores a placeholder, an export file carries the value inside an encrypted envelope, and the list never renders it.

The rule is short. If it should not sit in a plaintext file, type it `secret`.
{% endstep %}

{% step %}
#### Take the account

Press ⌃K to open the panel with the search field focused, type part of the name, then use ↑ and ↓ and press Return to open an element.

Press **use + copy**. Two things happen: the element is marked in use by you, and its primary field goes to the clipboard. The primary field is always the first field in the group's schema.

The row then shows a green badge with your name on it. Hover it for the age, the environments, and how many idle minutes remain before it releases itself.
{% endstep %}

{% step %}
#### Log in on the simulator

Set the collection's URL scheme first, either from the ▾ menu next to the collection name or from Settings.

Then press **login on sim**. Notchboard runs:

```bash
xcrun simctl openurl booted "<scheme>://debug/login?user=…&pass=…"
```

Your app's debug build needs the scheme registered and a handler that reads the query. `SampleApp/` in the repository is a working example you can install into a simulator to try the bridge before touching your own project.

If the deeplink succeeds and the element was free, it is marked in use automatically. Logging in as an account is using it.
{% endstep %}
{% endstepper %}

## When a deeplink cannot do it

Some logins a deeplink will never drive. SSO redirects, Okta, anything rendered in a WebView, any flow where your app never receives the URL.

For those, use **use + copy** for the username and **copy password** for the password, then paste them by hand. You still get the in-use mark, so teammates still see the account is taken.

## What's next?

{% content-ref url="../core-concepts/overview.md" %}
[overview](../core-concepts/overview.md)
{% endcontent-ref %}

{% content-ref url="../guides/team-rooms.md" %}
[team-rooms](../guides/team-rooms.md)
{% endcontent-ref %}
