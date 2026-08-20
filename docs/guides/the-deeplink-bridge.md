---
icon: link
description: >-
  Fire a login straight into the booted app, and what your app needs to receive
  it.
---

# The deeplink bridge

**login on sim** fires a URL into the booted simulator so your app logs itself in. It runs:

```bash
xcrun simctl openurl booted "<scheme>://debug/login?user=…&pass=…"
```

The username comes from the element's `username` field. The password comes from the group's first secret-typed field, read from memory, so the real value and not the on-disk placeholder.

Both are percent-encoded aggressively, against alphanumerics only, so an email's `@` and `+` and every punctuation character a generated password can carry survive the trip.

## Before you start

One thing decides whether the button appears at all: the element needs a non-empty field keyed `username`. If the group has no secret field, or that field is empty on this element, the URL carries only `user=`.

## Steps

{% stepper %}
{% step %}
#### Set the scheme on the collection

The scheme is per collection, because each catalogue describes one app. Two places to set it:

* The ▾ menu next to the collection name. The item reads **set deeplink scheme** while there is none, and shows the scheme once one is set.
* Settings → Simulator deeplink → Debug URL scheme.

`mythos`, `mythos:`, `mythos.` and `mythos://` all normalise to `mythos`.

{% hint style="warning" %}
Network schemes (`http`, `https`, `ftp`, `file`, `ws`, `wss`) are refused, so pasting your app's universal link can never fire credentials at a live host as query parameters.
{% endhint %}

The scheme is checked when you press the button, not when it is drawn. Without one, the button still appears, captioned "no URL scheme yet", and pressing it tells you where to set it.
{% endstep %}

{% step %}
#### Register the scheme in your debug build

Add the URL scheme to the debug build's `Info.plist`. `SampleApp/README.md` in the repository has the full block.
{% endstep %}

{% step %}
#### Handle the route

Two pieces, and nothing else:

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
{% endstep %}

{% step %}
#### Try it

Open an element and press **login on sim**.

If the deeplink succeeds and the element was free, it is marked in use automatically. Logging in as an account is using it. If `simctl` fails, nothing is marked.
{% endstep %}
{% endstepper %}

{% hint style="info" %}
`SampleApp/NotchDemo` in the repository is a runnable reference integration. Install it into a simulator to try the bridge before touching your own project.
{% endhint %}

## When to use copy password instead

Some logins a deeplink cannot drive. SSO redirects, Okta, anything rendered in a WebView, any flow where your app never receives the URL.

For those, use **use + copy** for the username and **copy password** for the password, then paste them by hand. You still get the in-use mark, so teammates still see the account is taken.

## One accepted exposure

`simctl` takes the URL as a command-line argument, so while that short-lived process runs the password is readable in the process list by other processes running as you. There is no argv-free way to hand `simctl` a URL.

These are shared test credentials on a local developer tool, so the trade-off is accepted and documented rather than hidden. Everything under Notchboard's own control, its log lines and `simctl`'s echoed stderr, is redacted.

## Troubleshooting

<details>

<summary>iOS asks "Open in \?" every time</summary>

It asks once per simulator install, not once per login. Accept it and it stops.

</details>

<details>

<summary>The button is not there</summary>

The element has no value in a field keyed `username`. The button is hidden rather than disabled in that case.

</details>

<details>

<summary>Firing while already signed in does nothing</summary>

Re-firing swaps accounts only if your handler resets the session first. That is your app's job, not Notchboard's.

</details>
