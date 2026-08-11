# Releasing Notchboard

How a build gets from this repo to someone else's Mac, what `brew install` really costs,
and which parts need an Apple account.

Two files do the work. `scripts/release.sh` builds and packages. `Casks/notchboard.rb` is
the Homebrew cask, written to be copied into a tap repository.

## The short version

A bare `brew install notchboard` is not available to this project and will not be for a
while. What works today is a personal tap:

```bash
brew tap thepearl/tap
brew install --cask notchboard
```

or, in one line:

```bash
brew install --cask thepearl/tap/notchboard
```

That tap already exists at `github.com/thepearl/homebrew-tap` (it currently carries the
`xcode-janitor-mcp` formula). Adding `Casks/notchboard.rb` to it is the whole job on the
Homebrew side. Nothing needs to be approved by anyone.

## Why a bare brew install notchboard is not on the table

The unprefixed name only works for casks accepted into `homebrew/homebrew-cask`, and that
repository has published acceptance criteria. The ones Notchboard fails or cannot yet be
measured against, quoted from Homebrew's own documentation (`brew --repository`, then
`docs/Package-Acceptance-Policy.md` and `docs/Acceptable-Casks.md`, both reviewed
2026-07-18):

Notability. A new package must demonstrate public interest beyond its author. A GitHub
project normally satisfies this by reaching at least 30 forks, 30 watchers or 75 stars,
raised to at least 90 forks, 90 watchers or 225 stars when the repository owner submits it
themselves. A repository less than 30 days old is normally not eligible. Notchboard's
repository is private, so it has none of these and cannot accumulate them until it is
public.

Public presence and maintenance. The software must have a public presence independent of
Homebrew, a homepage that explains the project, and active upstream maintenance with no
known unpatched security vulnerabilities.

Verifiable upstream distribution. The download must be published by the developer or by a
source the developer publicly endorses. A GitHub release on the project's own repository
satisfies this.

Platform rules. The cask must work on every operating system and architecture it declares,
must work on the latest major version of macOS, and must not require System Integrity
Protection or Gatekeeper to be disabled or bypassed.

That last line is where signing enters. Homebrew's acceptance criteria do not contain a
sentence saying "the app must be notarised". What they contain is the rule against
requiring Gatekeeper to be bypassed, and an unsigned download cannot be launched without
bypassing Gatekeeper. So notarisation is a practical consequence of a written rule rather
than a separately written rule. Treat it as required in effect.

Maintainer discretion applies on top of all of it. Meeting every criterion does not
guarantee acceptance, and Homebrew states that new submissions may be held to a higher
standard than existing packages.

None of this blocks a personal tap. Homebrew is explicit that software which does not meet
the official criteria can be maintained in a third-party tap, and that distribution through
one implies no Homebrew endorsement or support.

## The Gatekeeper reality

This is the part that actually decides whether the download is pleasant or miserable.

Notchboard currently builds with `CODE_SIGN_IDENTITY = "-"` and an empty `DEVELOPMENT_TEAM`
in every configuration. That is an ad-hoc signature. It is deliberate, because it means a
fresh clone builds and runs with no Apple account, and it is fine for a build you compiled
yourself on the machine you are running it on.

It is not fine for a download. Anything fetched over the network gets the
`com.apple.quarantine` attribute, and Homebrew applies that attribute to cask downloads
itself whenever macOS supports it. Current Homebrew has no supported opt-out. On first
launch macOS refuses a quarantined app with no valid Developer ID signature. The wording
varies by macOS version and by how the app was signed, and includes both "notchboard is
damaged and can't be opened. You should move it to the Trash." and "Apple could not verify
notchboard is free of malware". Neither one tells the user anything useful, and the
"damaged" phrasing in particular reads as a corrupt download rather than a policy decision.

The workarounds all make it worse. Telling people to run `xattr -d com.apple.quarantine`,
or to right-click and choose Open, or to approve the app in System Settings, is asking them
to disable a security check for a menu-bar agent that wants Accessibility permission. For
this app, of all apps, that is the wrong thing to teach.

There is exactly one path that avoids it. Sign with a Developer ID Application certificate,
notarise the archive with Apple, and staple the ticket. Then the download opens on a double
click with no dialog.

That requires membership of the Apple Developer Program, which costs 99 US dollars per year
(local pricing varies, and the current figure is on
https://developer.apple.com/programs/). It is the only way to make the download path
pleasant, and it is a recurring cost, not a one-off. If the membership lapses the
certificate stops being valid for new signatures, although already-notarised and stapled
builds keep working.

Worth knowing before paying. Notarisation itself is automated and free once you are a
member, it takes a few minutes per submission, and no human reviews the app. It is not App
Store review. Notchboard runs unsandboxed with hardened runtime on, which notarisation
accepts.

## Release checklist

Steps 1 to 3 need nothing but Xcode. Steps 4 to 6 need the paid account.

1. Decide the version. `MARKETING_VERSION` in the project is the source of truth, and
   `scripts/release.sh` reads it unless you pass `--version`.

2. Confirm the tree is green.

   ```bash
   xcodebuild -project notchboard.xcodeproj -scheme notchboard \
     -destination 'platform=macOS' test
   ```

3. Build and package.

   ```bash
   scripts/release.sh
   ```

   It builds Release for arm64 and x86_64, copies the app to `build/release/`, zips it with
   `ditto -c -k --keepParent`, prints the sha256, and then prints the exact commands for
   steps 4 to 6 with your paths already filled in. It is safe to re-run and it never touches
   codesign, notarytool or stapler itself.

   `ditto` rather than `zip` is not a preference. The Finder's Compress and `ditto` both
   preserve the symlinks and extended attributes inside an app bundle. Plain `zip` does not,
   and a bundle that lost them fails signature validation after the round trip.

4. Sign with Developer ID. Find your identity with
   `security find-identity -v -p codesigning`, then use the `codesign` line the script
   printed. Re-zip afterwards, because the signature lives inside the bundle.

5. Notarise and wait. Store the App Store Connect credential once with
   `xcrun notarytool store-credentials`, then submit with `--wait`. A rejection comes back
   with a log URL that names the offending binary.

6. Staple the ticket with `xcrun stapler staple`, re-zip one last time, and check the result
   with `spctl --assess --type execute --verbose`. Stapling is what lets a first launch
   succeed on a Mac that is offline.

7. Take the sha256 of the final zip. Every re-zip changes it, so only the last one counts.

8. Publish the release.

   ```bash
   gh release create "v1.0" build/release/notchboard-1.0.zip \
     --title "v1.0" --notes "..."
   ```

9. Update `Casks/notchboard.rb` in this repo with the new `version` and `sha256`, and copy
   the same file into `thepearl/homebrew-tap` under `Casks/notchboard.rb`. Keeping a copy
   here is what makes the cask reviewable alongside the code that decides its zap paths.

10. Verify the whole path on a machine that has never run the app.

    ```bash
    brew tap thepearl/tap
    brew install --cask notchboard
    ```

    Then launch it. A dialog at this point means step 4, 5 or 6 did not take.

## Setting up the tap for the first time

The tap repository already exists, so this is a one-off only if it ever needs recreating.

```bash
brew tap-new thepearl/homebrew-tap
gh repo create thepearl/homebrew-tap --public --push \
  --source "$(brew --repository thepearl/homebrew-tap)"
```

Casks go in `Casks/`, formulae at the root or in `Formula/`. A tap can hold both, so the
existing `xcode-janitor-mcp.rb` and a new `Casks/notchboard.rb` coexist without conflict.

## Checking the cask before publishing it

```bash
brew style Casks/notchboard.rb
```

Homebrew refuses to load a cask from a loose file path, so evaluating it takes a tap. The
quickest way is to copy the file into the real tap's working copy and ask for its info:

```bash
cp Casks/notchboard.rb "$(brew --repository thepearl/homebrew-tap)/Casks/"
brew info --cask thepearl/tap/notchboard
```

That evaluates every stanza. An unknown `zap` key or a malformed `depends_on` fails there,
not at install time.

`brew audit --cask --new` is the stricter check and the one homebrew-cask itself runs, but
it downloads the URL, so it only becomes useful once a release actually exists.

## What the app leaves behind

The cask's `zap` stanza covers the files. The paths come from the source, not from guesswork.

`~/Library/Application Support/Notchboard/` holds `state.json`, the whole catalogue, and
`state.json.corrupt` if a launch ever found the file unreadable (`AppStateStore.swift`).

`~/.notchboard/snapshots/` holds the rotating encrypted snapshots
(`SnapshotStore.swift`).

The usual per-bundle files that AppKit writes for any app, under `~/Library/Preferences/`,
`~/Library/Caches/` and `~/Library/Saved Application State/`, keyed on `flourix.notchboard`.

The login item, if launch at login was ever switched on. `SMAppService` registers it under
the app's own name and it outlives a plain uninstall, which is why the cask carries an
`uninstall login_item:` directive.

Keychain items are the gap. A cask has no directive for them, and deleting the login
keychain would take everything else with it, so `brew uninstall --zap notchboard` leaves
three services behind. Clearing them is manual, and each call removes one matching item, so
repeat until nothing is left to find:

```bash
security delete-generic-password -s flourix.notchboard.secrets   # secret field values
security delete-generic-password -s flourix.notchboard.rooms     # room passwords
security delete-generic-password -s flourix.notchboard.device    # snapshot sealing key
```

Deleting the device key makes every existing snapshot permanently unreadable, which is the
intended outcome when you are removing the app and not a thing to do casually otherwise.

## Sources

- https://docs.brew.sh/Package-Acceptance-Policy
- https://docs.brew.sh/Acceptable-Casks
- https://docs.brew.sh/Cask-Cookbook
- https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap
- https://developer.apple.com/programs/
- https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
