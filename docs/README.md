---
icon: hand-wave
description: >-
  A shared catalogue of test accounts and fixtures, docked to your iOS
  Simulator window, that shows who is using what.
---

# Welcome

Notchboard is a macOS menu-bar app that keeps your team's working test logins next to the simulator you are already looking at. It attaches a slim notch to the edge of the Simulator window, follows that window as it moves, and opens into a searchable catalogue on a click.

Pick an account, copy it or fire it straight into the booted app as a deeplink, and mark it in use so nobody logs in behind you.

Install it with Homebrew.

```bash
brew install --cask thepearl/tap/notchboard
```

The rest of the setup, granting Accessibility and docking to a simulator, is in the [installation guide](getting-started/installation.md).

***

{% hint style="info" icon="hammer" %}
**No Homebrew?** [Building from source](getting-started/installation.md) works too, with Xcode 26 or later and no Apple account needed.
{% endhint %}

## Where to start

<table data-card-size="large" data-view="cards"><thead><tr><th></th><th></th><th></th><th data-hidden data-card-target data-type="content-ref"></th></tr></thead><tbody><tr><td><h4><i class="fa-rocket-launch" style="color:$primary;">:rocket-launch:</i></h4></td><td><h4>Getting started</h4></td><td>Build the app, grant Accessibility, and dock it to a running simulator.</td><td><a href="getting-started/installation.md">getting-started/installation.md</a></td></tr><tr><td><h4><i class="fa-book" style="color:$primary;">:book:</i></h4></td><td><h4>Core concepts</h4></td><td>Collections, groups, elements, field types and environments.</td><td><a href="core-concepts/overview.md">core-concepts/overview.md</a></td></tr><tr><td><h4><i class="fa-graduation-cap" style="color:$primary;">:graduation-cap:</i></h4></td><td><h4>Guides</h4></td><td>Team rooms, the deeplink bridge, exports and the security model.</td><td><a href="guides/overview.md">guides/overview.md</a></td></tr><tr><td><h4><i class="fa-book-open" style="color:$primary;">:book-open:</i></h4></td><td><h4>Reference</h4></td><td>Settings, shortcuts, troubleshooting and terminology.</td><td><a href="reference/settings-and-shortcuts.md">reference/settings-and-shortcuts.md</a></td></tr></tbody></table>

## What it does

Where the minutes actually go, and what replaces them.

* Finding the staging account that still works, without scrolling a pinned chat message.
* Seeing that a teammate is already on it, before you log in and kick them out.
* Getting into the app without retyping a password on a simulator keyboard.
* Keeping promo codes, test cards, seeded users and deeplinks in one place per project.
* Onboarding someone on their first morning by sending one line instead of six.

## Main features

<table data-view="cards"><thead><tr><th></th><th></th></tr></thead><tbody><tr><td><h4>Docked, not another window</h4></td><td>The panel tracks the real Simulator window through the Accessibility API and moves with it. It never steals focus, so you can type in its search field while Simulator stays frontmost.</td></tr><tr><td><h4>In-use marks other people see</h4></td><td>Mark an account in use and everyone in the room sees who took it and when. It releases itself after an idle window you set.</td></tr><tr><td><h4>One-click login</h4></td><td>Fires a debug deeplink into the booted app, with a separate copy-password button for the SSO and WebView screens a deeplink cannot drive.</td></tr><tr><td><h4>End-to-end encrypted</h4></td><td>Every room payload is sealed with AES-GCM under a key derived from the room password. The broker relays bytes it cannot read, and you pick the broker.</td></tr></tbody></table>

## Platform support

| Target                   | Supported | Setup                                                                             |
| ------------------------ | :-------: | --------------------------------------------------------------------------------- |
| macOS 14 and later       |     ✅     | Homebrew cask, or build from source with Xcode 26 or later                        |
| Docking to the Simulator |     ✅     | Simulator.app running, plus the Accessibility permission                          |
| One-click login          |     ✅     | A booted simulator, a URL handler in your app, and a scheme set on the collection |
| Team room                |     ✅     | An MQTT 5 broker with retained messages, including a local mosquitto              |
| Physical iOS device      |     ⚠️    | Copy and paste only, `simctl` cannot reach a real device                          |
| Android or emulators     |     ❌     | Not supported, and not planned                                                    |
| Mac App Store build      |     ❌     | Impossible by design, the App Sandbox breaks docking                              |

## What it is not

Knowing the edges beats finding them the hard way.

* Not a password manager. This holds shared test credentials for a team. Your personal secrets belong somewhere with a different threat model.
* Not a production secrets store. The app warns you when an element mixes production with another environment, and that warning is the whole mechanism.
* Not a simulator automation tool. It fires one deeplink. Seeding fixtures and scripting flows are a different tool's job.
* Not a service. The broker is the only server, it only relays ciphertext, and you choose it.
