---
icon: bolt
description: Go from the install command to a panel docked beside your simulator.
---

# Quickstart

This quickstart gets the app running and docked as fast as possible. Configuration can wait until you have something on screen.

{% hint style="success" %}
**Estimated time: 5 minutes.** All you need is Homebrew and a simulator.
{% endhint %}

## Steps

{% stepper %}
{% step %}
#### Install it

```bash
brew install --cask thepearl/tap/notchboard
```

The download is signed and notarised, so the first launch is a normal one. [Installation](installation.md) covers the alternatives, a zip from the latest release or building from source.
{% endstep %}

{% step %}
#### Launch it

```bash
open /Applications/notchboard.app
```

Look for the half-filled square in the menu bar. There is no Dock icon.
{% endstep %}

{% step %}
#### Walk through setup

Four steps in their own window: a welcome screen, your name, your starting point, and the Accessibility permission.

For a first look, pick the sample catalogue. It comes with 4 groups and 20 elements to poke at.
{% endstep %}

{% step %}
#### Grant Accessibility

On the last setup step, click **grant access**. macOS shows its own dialog. Open System Settings, go to Privacy & Security then Accessibility, and turn the Notchboard switch on. The setup step polls in the background and flips to granted by itself.

{% hint style="info" %}
The system dialog is one-shot. Once you dismiss it, further clicks do nothing, which is why the button changes to **open System Settings** after the first attempt.
{% endhint %}

If the toggle will not stick, which happens on some managed Macs, click **continue without docking**. Everything works except docking, and you open the panel from the menu bar instead.
{% endstep %}

{% step %}
#### Verify it works

Start Simulator.app, then open the panel from the menu bar.

You should see a slim notch attached to the edge of the Simulator window, following it as you drag that window around. Click the notch and the catalogue opens.
{% endstep %}
{% endstepper %}

## What's next?

{% content-ref url="your-first-collection.md" %}
[your-first-collection](your-first-collection.md)
{% endcontent-ref %}

{% content-ref url="../guides/team-rooms.md" %}
[team-rooms](../guides/team-rooms.md)
{% endcontent-ref %}

{% content-ref url="../guides/the-deeplink-bridge.md" %}
[the-deeplink-bridge](../guides/the-deeplink-bridge.md)
{% endcontent-ref %}
