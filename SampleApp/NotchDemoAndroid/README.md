# NotchDemoAndroid

A minimal Android app that receives Notchboard's debug-login deeplink — the Android twin
of `SampleApp/NotchDemo`. It exists so the "login on sim" path can be exercised end to end
against a real app on an emulator, instead of stopping at the `adb` boundary.

It also doubles as the reference integration: what a real team's Android app has to add to
work with Notchboard is the two pieces below, and nothing else.

## Run it

No Gradle wrapper is committed. Either open this folder in Android Studio and press Run,
or with a locally installed Gradle (`brew install gradle`):

```bash
cd SampleApp/NotchDemoAndroid
gradle installDebug
```

Then in Notchboard, set the scheme to `notchdemo` under Settings, Debug deeplink (it starts
empty, and it is per collection). Open any element with a username and hit "login on sim".

To drive it by hand (the inner quotes matter — `adb shell` re-parses the URL on the
device, and an unquoted `&` truncates it):

```bash
adb shell am start -a android.intent.action.VIEW -d "'notchdemo://debug/login?user=qa.empty@acme.dev&pass=Sunflower-42'"
```

## The integration, in full

**1. Register the scheme** (`AndroidManifest.xml`, debug builds in a real app):

```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="notchdemo" android:host="debug" android:path="/login" />
</intent-filter>
```

**2. Handle the route** (`MainActivity.java`). The whole contract is `user` plus an
optional `pass`:

```java
Uri url = intent.getData();
if (url != null && "debug".equals(url.getHost()) && "/login".equals(url.getPath())) {
    String user = url.getQueryParameter("user");
    String pass = url.getQueryParameter("pass");
    // fill your login form and submit
}
```

`getQueryParameter` percent-decodes, so emails and passwords with symbols survive the trip.
Give the activity `android:launchMode="singleTop"` and handle `onNewIntent` too, or every
login stacks a fresh activity instead of switching accounts in place.

## Note on the password in the URL

Like `simctl` on iOS, `adb` takes the URL as a command-line argument, so the password is
briefly visible in the Mac's process list while the short-lived process runs. Android adds
one exposure of its own: on API ≤ 32 the system logs the intent's data URI verbatim to
logcat, credentials included (API 33+ redacts it to `scheme://host/...`). Both are
documented, accepted tradeoffs for shared test credentials on a local dev tool — see the
header of `notchboard/Docking/AdbBridge.swift`.
