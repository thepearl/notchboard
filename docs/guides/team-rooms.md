---
icon: users
description: >-
  Keep one collection in sync across Macs, end-to-end encrypted, over a broker
  you choose.
---

# Team rooms

A room is how two or more Macs keep one collection in sync, live. Edits, schema changes, deletions and in-use marks flow both ways as they happen, with no polling and no refresh.

By default nothing leaves your Mac. A collection joins a room only when you tell it to.

{% hint style="success" %}
**There is no Notchboard server.** You bring your own MQTT broker, and it only ever relays ciphertext. The broker operator sees topic names, message sizes and timing, and nothing else.
{% endhint %}

## Before you start

You will need an MQTT 5 broker. A managed one such as HiveMQ Cloud or EMQX Cloud works, and so does your own mosquitto.

<details>

<summary>What your broker has to support</summary>

Notchboard leans on more of MQTT 5 than a chat app would, so "speaks MQTT" is not quite the bar.

* MQTT 5.0. There is no 3.1.1 fallback.
* Retained messages, and enough of them. The retained set is the room's entire state, one message per group, per element, per live in-use mark and per member.
* QoS 1, in both directions.
* Wildcard subscriptions, plus publish and subscribe permission on `nb/<room>/#`.
* The `noLocal` subscription option, and overlapping subscriptions kept distinct rather than merged.
* Last Will and Testament with retain, which is how a Mac that dies ungracefully stops holding its marks.
* The Message Expiry Interval property, used only to age out deletion records.

Mosquitto, HiveMQ and EMQX all qualify. A managed broker with a low retained-message quota or a restrictive topic ACL will fail in ways the app can only report as a generic connection problem.

</details>

<details>

<summary>A local mosquitto, for trying it out</summary>

```bash
brew install mosquitto
"$(brew --prefix)"/opt/mosquitto/sbin/mosquitto -p 1883
```

Then use `mqtt://localhost:1883`. TLS is not required on localhost and no broker account is needed. This is also what the integration tests expect.

</details>

### Broker addresses

Three forms are accepted, and anything else is refused at connect rather than silently downgraded.

| Form                             | Default port | When                                                         |
| -------------------------------- | :----------: | ------------------------------------------------------------ |
| `mqtts://[user@]host[:8883]`     |     8883     | The normal case, TLS over TCP                                |
| `wss://[user@]host[:443][/path]` |      443     | MQTT over WebSocket and TLS, the corporate-firewall fallback |
| `mqtt://localhost[:1883]`        |     1883     | Plaintext, loopback only, for a local mosquitto              |

A broker username rides inside the URL, as in `mqtts://team@broker.example:8883`. The broker password is typed separately in the setup dialog.

{% hint style="danger" %}
Plaintext `mqtt://` to anything other than `localhost`, `127.0.0.1` or `::1` is refused. There is no flag to weaken it. Sending credentials over cleartext to a real host is exactly the mistake the refusal exists to prevent.
{% endhint %}

TLS trust comes from the system store and cannot be customised, so a self-hosted broker with a self-signed or private-CA certificate does not work.

## Steps

{% stepper %}
{% step %}
#### Create the room

One person does this, once. Open the ▾ menu next to the collection name and pick **set up team room**.

Fill in the broker address, a room name (lowercase letters, digits and dashes, such as `acme-mobile`), the broker username and password if your broker needs an account, and a room password. Generate sits beside the room password field.

The room name namespaces your topics on the broker, so pick something specific to your team.

{% hint style="warning" %}
Copy the room password now. It goes straight to the Keychain and is never displayed again.
{% endhint %}
{% endstep %}

{% step %}
#### Copy the invite

▾ menu → **copy room invite**. This puts one line on your clipboard:

```
notchboard-room:eyJicm9rZXJVUkwiOi…
```

It is base64url of the room config. Readable inside it: the broker address, the broker username, and the room name. Not readable: the broker account password, sealed under the room key. Not present at all: the room password.

The invite is a paste-code rather than a clickable URL on purpose. It needs no LaunchServices registration, survives being sent through chat or email, and cannot be triggered by a stray click.
{% endstep %}

{% step %}
#### Send the two pieces separately

Paste the invite line into your team chat. Send the room password another way, out of band, like a wifi password.

The invite on its own gives away only where the room is, not what is in it. Treat it like an internal link rather than a public one.
{% endstep %}

{% step %}
#### Join

Three doors, all the same flow. Paste the invite, type the room password.

* ▾ menu → **join with an invite**
* Menu bar → **Join Room with Invite**
* Onboarding → **join a team room** as your starting point

The broker's retained messages then hand the new joiner the entire catalogue, with no history protocol of our own.
{% endstep %}
{% endstepper %}

{% hint style="danger" %}
**Joining an existing room is destructive on first connect.** The room's catalogue replaces whatever that collection held locally, including its Keychain secrets, because the room is the source of truth once you are in it. A local snapshot is forced immediately before, and that snapshot is the only undo. Join with a fresh collection when you have anything you want to keep.
{% endhint %}

If the room is empty instead, your local catalogue seeds it.

## The room password is the only key

Everything published to the room is AES-GCM ciphertext under a key derived from the room password. Consequences worth knowing:

* Anyone with the room password can read the room. Anyone without it can read nothing, the broker operator included.
* A wrong room password is detected before anything is applied, so plausible garbage never reaches your catalogue.
* Removing someone means moving to a new room name. Rotating the password in place is refused, because everything the broker holds is retained ciphertext under the old key and nothing purges it. You would lock out the whole team, yourself included.

The room password is stored in the Keychain under service `flourix.notchboard.rooms`. The full reasoning is in the [security model](security-model.md).

## What syncs and what does not

Syncs: element content (name, values including secrets, note, environments, last-used stamp), group schemas and their order, the collection name, deletions, and in-use marks.

Does not sync, deliberately:

* Favourites. Starring a row is personal.
* The notify-when-free watch list. Also personal, and in-memory only.
* Your deeplink scheme and every setting in Settings.
* Snapshots.

Conflicts resolve last-write-wins on the element, with the member id breaking exact ties deterministically on every Mac.

## Presence

Once connected, the panel header shows "· N online", counting you. The list footer carries the same count on the right. On the left it shows how many elements are in use, then the connection word: local, connecting, live, room offline, or room unreachable.

The connection dot is the amber square beside the wordmark, and the same dot on the notch when collapsed. Amber means local or connecting, green means live, red means the room is unreachable. It never animates.

An offline member's in-use marks render free, so a colleague who shut their laptop does not leave rows locked. Their mark is untouched and returns when they do. Closing the lid publishes a proper goodbye, so presence flips within a second or two rather than waiting out the 45 second keepalive.

Reconnection is automatic with exponential backoff from 1 to 60 seconds. You keep working locally the whole time, and everything you changed while offline is pushed on reconnect.

## Leaving

▾ menu → **leave room**, or Settings → Team room → Leave Room.

The collection keeps everything it has and stops sending and receiving. The room password is deleted from this Mac's Keychain, so rejoining means pasting the invite and the password again.

## Honest rough edges

Documented rather than hidden.

<details>

<summary>A mark released while offline comes back briefly</summary>

It is reinstated by its own retained copy on reconnect, then ages out through the auto-release sweep. A mark is a status light, and a minute of staleness beat adding a special case to the protocol.

</details>

<details>

<summary>Deletion records expire after 30 days</summary>

A Mac that was offline longer than that can resurrect a deleted row.

</details>

<details>

<summary>Simultaneous edits lose one side</summary>

Two people editing the same element within the same instant means one edit is silently dropped. Last-write-wins is the accepted trade here.

</details>

<details>

<summary>Restoring a snapshot leaves stale sessions</summary>

Restoring does not tear down sessions for collections the restore removed. They go on the next relaunch. Deleting a collection handles it properly.

</details>

## Troubleshooting

<details>

<summary>The dot stays red</summary>

Check the broker address form first. A plaintext `mqtt://` pointed at a real host is refused by design, with a message telling you to use `mqtts://`.

If the address is right, the broker is the next suspect. A restrictive topic ACL that blocks `nb/<room>/#`, or a retained-message quota, surfaces only as a generic connection problem.

</details>

<details>

<summary>Joining fails immediately, before any connection attempt</summary>

That is a wrong room password, detected with certainty. The broker account password inside the invite is sealed under the room key, so a seal that will not open proves the password is wrong without a round trip.

</details>

<details>

<summary>A teammate's rows all show as free</summary>

They are offline. An offline member's marks render free so their shut laptop does not leave rows locked. The marks themselves are untouched and return when they do.

</details>
