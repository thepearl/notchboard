# Contributing to notchboard

Thanks for looking. This page covers building, testing, and what a pull request needs to pass.

## Getting set up

```bash
git clone https://github.com/thepearl/notchboard.git
cd notchboard
open notchboard.xcodeproj
```

You need Xcode 26 or later. The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which
Xcode 16 does not recognise. It ignores the setting instead of rejecting it, so an older Xcode fails
on the first implicitly main-actor initialiser rather than on the setting itself.

No Apple developer account is needed. Signing is ad-hoc with an empty development team in every
configuration, so a fresh clone builds and runs as-is. Do not commit a team id back in.

## Building and testing

```bash
xcodebuild -project notchboard.xcodeproj -scheme notchboard -configuration Debug build
```

```bash
xcodebuild -project notchboard.xcodeproj -scheme notchboard -destination 'platform=macOS' test
```

Or through fastlane, which is what CI runs:

```bash
bundle install && bundle exec fastlane test
```

Three suites need something your machine may not have, and they skip rather than fail:

| Suite | Needs |
|---|---|
| `MosquittoIntegrationTests` | an MQTT broker on `localhost:1883` |
| `PeerHarnessTests` | the same broker |
| `SimctlBridgeIntegrationTests` | a booted simulator with the `SampleApp` demo installed |

A green run on a bare machine does not cover the room or the deeplink bridge. Boot both before
trusting one:

```bash
brew install mosquitto && "$(brew --prefix)"/opt/mosquitto/sbin/mosquitto -p 1883
```

## Writing tests

Tests use Swift Testing, never XCTest. Import `Testing`, write `@Test` functions and `#expect`
assertions.

Skips go on the suite as an `.enabled(if:)` trait, never as a `try #require` inside a test body.
Swift Testing has no in-body skip, so a `#require` gate records a failed expectation and turns a
clean clone's first test run red. The probes that back those traits live in
`notchboardTests/Support/`, because a trait written in an attribute cannot reach a private static
member of the type it annotates.

Timing-sensitive tests poll rather than sleep for a fixed interval. The suite is main-actor
isolated, so a heavy neighbour can delay a continuation past any hard-coded deadline, and the test
then fails only in full runs.

## Before opening a pull request

Read [CLAUDE.md](CLAUDE.md) first if you are changing anything structural. It lists the constraints
that are load-bearing, each with the bug that produced it. The App Sandbox stays off, the panel
stays non-activating, the global chords stay on Carbon, and nothing animates in the panel at rest.
Those are not preferences.

Then:

- The build is clean, with no new warnings in app sources.
- The full suite passes, including the environment-gated suites if your change touches sync or the
  deeplink bridge.
- `swiftlint lint` reports no new violations. The existing ones are advisory in CI until they are
  burned down, so do not add to the pile.
- [vision.md](vision.md) section 13 is updated if the change alters what the app does. That section
  is the running implementation log and it is how the next person learns why something is the way
  it is.

Commit messages are `<type>: <description>`, where type is one of feat, fix, refactor, docs, test,
chore, perf, ci.

## Using an AI assistant

Encouraged, especially on bug fixes. [ABOUT_AI_USAGE.md](ABOUT_AI_USAGE.md) has the two conditions
and the list of things an assistant reliably gets wrong in this codebase.

## House rules for user-facing copy

Three of them, each from a real complaint:

The word "claim" never appears in front of a user. The UI says "in use", "used by", "use + copy".
Internal identifiers keep their names.

Explain the consequence, not the mechanism. A settings footer or a dialog preamble is one or two
lines. How a feature works internally belongs in vision.md.

Action labels carry no trailing ellipsis.

## Reporting something

Open an [issue](https://github.com/thepearl/notchboard/issues). For anything about the room, say
which broker you were on and whether it was over TLS, since most room behaviour depends on both.

Do not put real credentials in an issue, a test collection you attach, or a room on a public broker.
The app is a place to keep shared test accounts, and the test in that sentence is doing real work.
