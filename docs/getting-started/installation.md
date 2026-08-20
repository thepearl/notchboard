---
icon: download
description: Install Notchboard with Homebrew, or build it from source.
---

# Installation

Notchboard has no Dock icon. It is a menu-bar item plus a floating panel, and nothing else. Installing a release takes a minute, and building from source needs no Apple account.

## Install with Homebrew

```bash
brew install --cask thepearl/tap/notchboard
```

The download is signed with a Developer ID certificate and notarised by Apple, so the first launch is the normal once-only confirmation for an app from the internet, and nothing worse.

## Without Homebrew

Download `notchboard-<version>.zip` from the [latest release](https://github.com/thepearl/notchboard/releases/latest), unzip it, and drag `notchboard.app` into Applications. Same notarised build, same result.

## What you need

* macOS 14.0 (Sonoma) or later.
* An iOS simulator, if you want the docked presentation. That means Xcode's Simulator.app with at least one iOS runtime. The app is fully usable without one, as an undocked panel opened from the menu bar.

## First launch

Look for the half-filled square in the menu bar. There is no Dock icon, and the menu-bar item is the entry point for everything.

Setup asks for the Accessibility permission on its last step. Notchboard reads the Simulator window's position so the panel can sit against its edge and follow it around, and reading another app's window frame is exactly what that permission gates. Click **grant access**, then turn the Notchboard switch on in System Settings under Privacy & Security, Accessibility. The setup step polls in the background and flips to granted by itself.

If the toggle will not stick, which happens on some managed Macs, click **continue without docking**. Everything works except docking, and you open the panel from the menu bar instead.

## Updating

Releases keep the Accessibility grant, because every release carries the same signing identity. A self-built copy loses the grant on each rebuild, and you grant it again.

## Uninstalling

```bash
brew uninstall --cask notchboard
```

That quits the app and removes the login item. Adding `--zap` also deletes the data directories, `~/Library/Application Support/Notchboard` and `~/.notchboard`.

The three Keychain entries stay manual either way:

```bash
security delete-generic-password -s flourix.notchboard.secrets
security delete-generic-password -s flourix.notchboard.rooms
security delete-generic-password -s flourix.notchboard.device
```

Each call removes one matching item, so repeat each line until it reports nothing left to find.

## Building from source

You need macOS 14 or later and Xcode 26 or later. An older Xcode fails loudly, on the first implicitly main-actor initialiser. The project has one Swift package dependency, [mqtt-nio](https://github.com/swift-server-community/mqtt-nio), fetched on the first build, so later builds work offline.

```bash
git clone https://github.com/thepearl/notchboard.git
cd notchboard
xcodebuild -project notchboard.xcodeproj -scheme notchboard -configuration Debug build
```

[INSTALL.md](https://github.com/thepearl/notchboard/blob/master/INSTALL.md) has the full detail, including where the built app lands, signing with your own identity, and troubleshooting a first launch.

## What's next?

{% content-ref url="quickstart.md" %}
[quickstart](quickstart.md)
{% endcontent-ref %}
