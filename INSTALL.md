# Installing notchboard

Notchboard is a macOS menu-bar agent that docks a catalogue of test accounts and fixtures to the
iOS Simulator window. This page takes you from a fresh clone to a panel docked beside a running
simulator.

There is no prebuilt download yet. Building from source is the only way to get the app today.
The reason is signing and notarisation, not effort: a zip that Homebrew or a browser downloads
carries the quarantine attribute, and macOS refuses a quarantined app that has no Developer ID
signature. The full reasoning and the release process are in [docs/RELEASING.md](docs/RELEASING.md).

## Requirements

macOS 14.0 (Sonoma) or later. `MACOSX_DEPLOYMENT_TARGET` is 14.0 in every build configuration.

Xcode 26 or later, and this one is measured rather than inferred. The project sets
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which Xcode 16 does not recognise. It ignores the
setting rather than rejecting it, so the build fails on the first implicitly main-actor
initialiser instead of on the setting itself. CI pins the `macos-26` image for that reason, since
`macos-latest` still points at macOS 15. On an older Xcode the failure is loud, not subtle.

A network connection for the first build. The project has one Swift package dependency,
[mqtt-nio](https://github.com/swift-server-community/mqtt-nio) 2.13.0, which pulls in swift-nio,
swift-nio-ssl, swift-nio-transport-services, swift-log, swift-atomics, swift-collections and
swift-system. Exact revisions are pinned in
`notchboard.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. Later builds work
offline once the packages are resolved.

An iOS simulator, if you want the docked presentation. Xcode's Simulator.app plus at least one iOS
runtime. The app is fully usable without one, as an undocked panel opened from the menu bar.

No Apple developer account, and no fonts to install. Space Grotesk and JetBrains Mono are bundled in
`notchboard/Fonts` and registered at runtime.

## Building from source

```bash
git clone https://github.com/thepearl/notchboard.git
cd notchboard
```

### From the command line

```bash
xcodebuild -project notchboard.xcodeproj \
           -scheme notchboard \
           -configuration Debug \
           -derivedDataPath build \
           build
```

`-derivedDataPath build` is optional but worth it. It puts the product at a path you can predict,
and `build/` is already in `.gitignore`.

### From Xcode

Open `notchboard.xcodeproj`, pick the `notchboard` scheme with My Mac as the destination, and press
⌘B. Xcode resolves the Swift packages on first open, which takes a minute or two.

### Signing

Nothing to configure. The project ships `CODE_SIGN_STYLE = Manual` with `CODE_SIGN_IDENTITY = "-"`
(ad-hoc) and an empty `DEVELOPMENT_TEAM` in every configuration, so a clone builds with no Apple
account and no team selected.

If you do have a team and want your own identity, override the settings instead of editing tracked
files:

```bash
xcodebuild -project notchboard.xcodeproj -scheme notchboard -configuration Debug \
           -derivedDataPath build build \
           CODE_SIGN_STYLE=Automatic \
           DEVELOPMENT_TEAM=YOURTEAMID \
           CODE_SIGN_IDENTITY="Apple Development"
```

Or keep the same three lines in an `.xcconfig` file outside the repository and pass it with
`-xcconfig`. Xcode's Signing & Capabilities tab works too, with one caveat: it writes your team ID
into `project.pbxproj`, which then shows up in `git status` and in any patch you send.

## Where the built app lands

With `-derivedDataPath build`:

```
build/Build/Products/Debug/notchboard.app
```

Without it, Xcode uses its shared DerivedData folder:

```
~/Library/Developer/Xcode/DerivedData/notchboard-<random-suffix>/Build/Products/Debug/notchboard.app
```

Copy it out and run it from `/Applications`:

```bash
cp -R build/Build/Products/Debug/notchboard.app /Applications/
open /Applications/notchboard.app
```

Do this before granting the Accessibility permission. macOS binds that grant to the exact binary it
was given, so a grant made to a DerivedData build stops applying the moment you rebuild, and you
have to grant it again.

A locally built app is not quarantined, so Gatekeeper does not block it.

## First run

Notchboard has no Dock icon. It is a menu-bar item plus a floating panel, and nothing else. Look for
the half-filled square in the menu bar.

Setup is four steps in its own window.

1. Welcome. One button, "get started".
2. Your name. This is the label other people see on elements you mark as in use. It cannot be empty.
3. Your starting point. Four options, and you can change any of it later.
   - Sample catalogue, 4 groups and 20 elements to poke at. This is the default and the fastest way
     to see what the app does.
   - Empty catalogue, one "users" group with nothing in it.
   - Import a collection file, a `.notchboard` file exported from another Mac. You will be asked for
     the file password.
   - Join a team room, if a teammate sent you an invite. Paste the `notchboard-room:` line into the
     first field and the room password into the second. The catalogue arrives from the room.
4. The Accessibility permission. Covered in full below.

There is a "back" link from step 2 onwards, and the red traffic light quits setup with a
confirmation.

If Simulator is running when you finish, the panel docks to it as a slim notch and a coach mark
points at it. If Simulator is not running, you land in the undocked panel instead, and the coach mark
waits for the first time a simulator appears.

## The Accessibility permission

Notchboard reads the Simulator window's position so it can sit against its edge and follow it around.
Reading another application's window geometry is exactly what the Accessibility permission gates, so
there is no way around it. Nothing is recorded or captured, and the app asks for no other permission
at launch.

On step 4, click "grant access". macOS shows its own dialog. Open System Settings, go to
Privacy & Security then Accessibility, and turn the Notchboard switch on. The setup step polls in the
background and flips to "granted" by itself, with no need to come back and click anything.

The system dialog is one-shot. Once you dismiss it, further clicks do nothing, which is why the
button changes to "open System Settings" after the first attempt. That button takes you straight to
the right pane.

If the toggle will not stick, which happens on some managed Macs, click "continue without docking".
Setup finishes and the app works, with one thing missing: it will not dock to the Simulator window.
You open the panel from the menu bar instead, and you can grant access later.

Two things worth checking when the toggle keeps flipping back:

- The entry in the list must be the copy of the app you actually launch. If you granted it to a
  DerivedData build and then copied a new build to `/Applications`, select the stale entry, remove it
  with the minus button, and grant again from the app you are running.
- After a rebuild, quitting and relaunching the app is sometimes needed before macOS re-reads the
  grant.

## Running it

The menu-bar item is the entry point for everything:

- Toggle Expand / Collapse switches between the slim notch and the full panel.
- Show Panel (Undocked) opens the panel free of the Simulator window, and changes to
  "Dock to Simulator Again" while it is on. This is the fallback when Simulator is not running or
  Accessibility is not granted.
- Join Room with Invite, Export Collection, Import Collections and Restore Snapshot.
- Settings, also ⌘, from the panel.
- Quit Notchboard.

The default shortcuts are ⌃K to open the catalogue with the search field focused, and ⌃N to open the
add-element form. They work from other applications, but only while Xcode, Simulator or Notchboard
itself is frontmost, and only while the panel is there to respond. Switch to Terminal and ⌃K goes
back to being kill-line. Settings offers ⌘ and ⌥⌘ as alternatives if ⌃ clashes with something you
use. Inside the panel, the plain ⌘K and ⌘N chords work as well.

Simulator must be running for the docked presentation. The panel attaches to the right edge of the
Simulator window by default, and Settings can move it to the left. Everything else about the app
works without a simulator through the undocked panel.

## Troubleshooting

No Simulator running, so nothing appears. Open the menu-bar item and choose Show Panel (Undocked).
The panel opens in the middle of the screen and behaves the same.

Accessibility is granted but nothing docks. Confirm the entry in System Settings points at the app
you are launching, remove and re-add it if you have rebuilt since granting, then quit and relaunch
Notchboard. Make sure the Simulator window is actually on screen, since a minimised or hidden
Simulator has no frame to dock against.

The panel disappeared behind another window. This is deliberate. The panel floats above everything
only while Simulator or Notchboard is frontmost, and drops to an ordinary window level otherwise, so
that a docked panel does not hover over your browser while the Simulator it belongs to is buried.
Click the Simulator window to bring it back, or use Show Panel (Undocked), which always floats.

The app was rebuilt and the permission stopped applying. Copy the new build over
`/Applications/notchboard.app`, remove the Notchboard row in System Settings, Privacy & Security,
Accessibility with the minus button, then relaunch and grant again. Running from `/Applications`
rather than DerivedData keeps this from repeating.

"Your catalogue couldn't be opened" at launch. The state file could not be read, so it was moved
aside to `~/Library/Application Support/Notchboard/state.json.corrupt` and setup starts fresh. The
alert offers Show in Finder. The original file is intact, so nothing is lost yet. If you had been
using the app for a while, try Restore Snapshot from the menu bar, which reads the encrypted
snapshots in `~/.notchboard/snapshots`.

macOS asks whether notchboard may use a Keychain item, and asks again after every rebuild. This is
a side effect of building it yourself. A Keychain item remembers which binary created it, and an
ad-hoc signature is the binary's own hash, so a rebuilt app is a different application as far as
macOS is concerned. Click Always Allow. If you rebuild often and the prompts get tiresome, run the
copy in `/Applications` for daily use and keep rebuilding separately, or sign with your own
Developer ID, which gives every build the same identity. The items live under
`flourix.notchboard.secrets`, `flourix.notchboard.rooms` and `flourix.notchboard.device` in Keychain
Access if you want to review or reset the approvals.

## Running the tests

```bash
xcodebuild -project notchboard.xcodeproj \
           -scheme notchboard \
           -destination 'platform=macOS' \
           test
```

Or through fastlane, which is what CI runs:

```bash
bundle install
bundle exec fastlane test
```

The suite is green on a clean clone with nothing else installed. Three suites skip themselves when
their environment is missing, rather than failing, so a fresh machine does not get a red run for
something it was never set up to do.

Two of them need an MQTT broker on `localhost:1883`:

```bash
brew install mosquitto
"$(brew --prefix)"/opt/mosquitto/sbin/mosquitto -p 1883 -v
```

Leave that running in another terminal and re-run the tests to cover `MosquittoIntegrationTests` and
`PeerHarnessTests`, which drive two complete peers through a real broker.

The third needs a booted simulator:

```bash
xcrun simctl list devices    # pick a device name your runtimes actually have
xcrun simctl boot 'iPhone 16'
open -a Simulator
```

That suite exercises the deeplink bridge for real. `SampleApp/NotchDemo` is a small app that
registers the `notchdemo://` scheme for it to fire at, with its own README.

## Uninstalling

In this order, because the first step needs the app to still be there.

1. Open Settings from the menu bar and turn off "Launch at login". The app unregisters its own login
   item. Skipping this leaves the login item behind after the app is gone. If you have already
   deleted the app, remove it by hand in System Settings, General, Login Items.
2. Quit Notchboard from the menu bar.
3. Delete the app.

   ```bash
   rm -rf /Applications/notchboard.app
   ```

4. Delete its data.

   ```bash
   rm -rf ~/Library/Application\ Support/Notchboard
   rm -rf ~/.notchboard
   ```

   The first holds `state.json`, the catalogue and settings, plus `state.json.corrupt` if a launch
   ever found the file unreadable. The second holds the encrypted snapshots.

5. Remove the Keychain items. Secret field values, room passwords and the snapshot sealing key live
   in the login keychain under three services:

   - `flourix.notchboard.secrets`
   - `flourix.notchboard.rooms`
   - `flourix.notchboard.device`

   In Keychain Access, select the login keychain, search for `flourix.notchboard`, select the
   matching entries and delete them. From the terminal, each call removes one matching item, so
   repeat each line until it reports nothing left to find:

   ```bash
   security delete-generic-password -s flourix.notchboard.secrets
   security delete-generic-password -s flourix.notchboard.rooms
   security delete-generic-password -s flourix.notchboard.device
   ```

6. Remove the stale permission rows. System Settings, Privacy & Security, Accessibility, select
   Notchboard and click minus. Do the same under Notifications if you ever allowed notify-when-free
   alerts.

A few files that AppKit writes for any bundle identifier may also exist, and are safe to delete:

```bash
rm -rf ~/Library/Caches/flourix.notchboard
rm -f  ~/Library/Preferences/flourix.notchboard.plist
rm -rf ~/Library/Saved\ Application\ State/flourix.notchboard.savedState
```
