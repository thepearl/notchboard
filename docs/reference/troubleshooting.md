---
icon: wrench
description: The failures people actually hit, and what to do about each.
---

# Troubleshooting

## Docking

<details>

<summary>Nothing appears at all</summary>

Simulator is probably not running. Open the menu-bar item and choose **Show Panel (Undocked)**. The panel opens in the middle of the screen and behaves the same in every respect except docking.

</details>

<details>

<summary>Accessibility is granted but nothing docks</summary>

Three things to check, in order.

1. The entry in System Settings points at the app you are actually launching. If you granted it to a DerivedData build and then copied a new build to `/Applications`, remove the stale entry with the minus button and grant again.
2. Quit and relaunch Notchboard. After a rebuild, macOS sometimes needs that before it re-reads the grant.
3. The Simulator window is actually on screen. A minimised or hidden Simulator has no frame to dock against.

</details>

<details>

<summary>The Accessibility toggle will not stick</summary>

This happens on some managed Macs. Click **continue without docking** during setup. Everything works except docking, and you can grant access later.

</details>

<details>

<summary>The panel disappeared behind another window</summary>

This is deliberate. The docked panel floats above everything only while Simulator or Notchboard is frontmost, and drops to an ordinary window level otherwise, so a docked panel does not hover over your browser while the simulator it belongs to is buried.

Click the Simulator window to bring it back, or use **Show Panel (Undocked)**, which always floats.

</details>

## Rebuilding

<details>

<summary>The permission stopped applying after a rebuild</summary>

Signing is ad-hoc, so the signature is the binary hash and every rebuild is a different app as far as macOS is concerned.

Copy the new build over `/Applications/notchboard.app`, remove the Notchboard row in System Settings, Privacy & Security, Accessibility with the minus button, then relaunch and grant again. Running from `/Applications` rather than DerivedData keeps this from repeating.

</details>

<details>

<summary>macOS keeps asking about a Keychain item</summary>

Same cause. A Keychain item remembers which binary created it, and a rebuilt ad-hoc app is a different application.

Click **Always Allow**. If the prompts get tiresome, run the copy in `/Applications` for daily use and keep rebuilding separately, or sign with your own Developer ID, which gives every build the same identity.

The items live under `flourix.notchboard.secrets`, `flourix.notchboard.rooms` and `flourix.notchboard.device` in Keychain Access if you want to review or reset the approvals.

</details>

<details>

<summary>The build fails on an implicitly main-actor initialiser</summary>

You are on an older Xcode. The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which Xcode 16 ignores rather than rejects, so the failure lands somewhere other than the setting. Xcode 26 or later is required.

</details>

## Data

<details>

<summary>"Your catalogue couldn't be opened" at launch</summary>

The state file could not be read, so it was moved aside to `~/Library/Application Support/Notchboard/state.json.corrupt` and setup starts fresh. The alert offers Show in Finder, and the original file is intact, so nothing is lost yet.

If you had been using the app for a while, try **Restore Snapshot** from the menu bar.

</details>

<details>

<summary>Secret fields are empty after moving to another Mac</summary>

Copying `state.json` alone leaves them empty, because the real values live in the Keychain and the Keychain does not come with the file.

Use an encrypted export, or a team room. Snapshots do not travel either, since their sealing key is device-local by design.

</details>

## Rooms

<details>

<summary>The connection dot stays red</summary>

Check the broker address form first. A plaintext `mqtt://` pointed at anything other than localhost is refused by design.

If the address is right, suspect the broker. A restrictive topic ACL blocking `nb/<room>/#`, or a retained-message quota, surfaces only as a generic connection problem.

A self-hosted broker with a self-signed or private-CA certificate will never connect, because TLS trust comes from the system store and there is no code path for adding a trust anchor.

</details>

<details>

<summary>Joining fails before any connection attempt</summary>

That is a wrong room password, detected with certainty. The broker account password inside the invite is sealed under the room key, so a seal that will not open proves the password is wrong without a round trip.

</details>

<details>

<summary>A deleted row came back</summary>

Deletion records expire after 30 days on the broker. A Mac that was offline longer than that can resurrect a deleted row. Delete it again from the Mac that has caught up.

</details>

## The deeplink

<details>

<summary>The login on sim button is missing</summary>

The element has no value in a field keyed `username`. The button is hidden rather than disabled in that case.

</details>

<details>

<summary>The button says "no URL scheme yet"</summary>

The collection has no deeplink scheme. Set it from the ▾ menu next to the collection name, or in Settings. It is stored per collection.

</details>

<details>

<summary>Nothing happens in the app</summary>

Check that the debug build registers the scheme in its `Info.plist` and that the handler matches host `debug` and path `/login`. `SampleApp/NotchDemo` in the repository is a runnable reference to compare against.

</details>

## Homebrew

<details>

<summary>Homebrew reports a checksum mismatch</summary>

The tap's cask is stale against the latest release. Run `brew update`, then retry the install.

If that does not clear it, `brew uninstall --cask notchboard --zap` is the clean-slate path, followed by `brew install --cask thepearl/tap/notchboard`. Keychain entries stay through the zap, so your secrets survive a reinstall.

</details>
