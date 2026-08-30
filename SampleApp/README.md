# NotchDemo

A minimal iOS app that receives Notchboard's debug-login deeplink. It exists so the
"login on sim" path can be exercised end to end against a real app, instead of stopping at
the `simctl` boundary.

It also doubles as the reference integration: what a real team's app has to add to work with
Notchboard is the two pieces below, and nothing else.

## Run it

```bash
cd SampleApp
xcodebuild -project NotchDemo.xcodeproj -target NotchDemo -configuration Debug -sdk iphonesimulator build CODE_SIGNING_ALLOWED=NO
xcrun simctl install booted build/Debug-iphonesimulator/NotchDemo.app
xcrun simctl launch booted flourix.notchdemo
```

Then in Notchboard, set the scheme to `notchdemo` under Settings, Debug deeplink (it starts
empty, and it is per collection). Open any element with a username and hit "login on sim".

To drive it by hand:

```bash
xcrun simctl openurl booted "notchdemo://debug/login?user=qa.empty@acme.dev&pass=Sunflower-42"
```

## The integration, in full

**1. Register the scheme** (`Info.plist`, debug builds in a real app):

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>flourix.notchdemo.deeplink</string>
        <key>CFBundleURLSchemes</key>
        <array><string>notchdemo</string></array>
    </dict>
</array>
```

**2. Handle the route** (`ContentView.swift`). The whole contract is `user` plus an optional
`pass`:

```swift
.onOpenURL { url in
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          components.host == "debug", components.path == "/login",
          let user = components.queryItems?.first(where: { $0.name == "user" })?.value
    else { return }
    let pass = components.queryItems?.first(where: { $0.name == "pass" })?.value
    // fill your login form and submit
}
```

That's it. Notchboard percent-encodes both values, so emails and passwords with symbols
survive the trip.

## What testing this actually revealed

**iOS asks for confirmation the first time.** Firing a custom scheme from outside the app
raises an "Open in NotchDemo?" alert with Cancel/Open. Verified on iOS 26.4: it appears on the
*first* deeplink only. Every subsequent one switches accounts instantly with no prompt, so the
cost is one tap per simulator install, not one per login. Worth knowing before assuming the
bridge is broken on first use.

**Re-firing while signed in swaps accounts cleanly.** The handler resets the session before
filling the form, so going from one test account to another is a single Notchboard click with
no sign-out step.

## Note on the password in the URL

`simctl` takes the URL as a command-line argument, so the password is briefly visible in the
process list to other processes running as you. This is a documented, accepted tradeoff for
shared test credentials on a local dev tool — see the header of
`notchboard/Docking/SimctlBridge.swift`. If that ever stops being acceptable, the fix is to
pass only the username here and have the target app resolve the secret itself.
