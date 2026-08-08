# Notchboard team room — QA test plan

First multi-human test of the sync room (vision.md §13.10). Everything below has passed
automated tests on one Mac. What only you can test: two real people, two real Macs, a
real network between them, and whether the flow makes sense without anyone explaining it.

Time needed: about 45 minutes with two people. A third person makes T17 possible.

---

## Ground rules

- **Test data only.** This round uses a public MQTT broker. Payloads are end-to-end
  encrypted under your room password, so nobody can read them, but the rule stands
  anyway: fake accounts, fake passwords, nothing from a real project.
- One person is the **host** (creates the room, owns the catalogue). Everyone else is a
  **joiner**. Roles matter for the steps below.
- Note the time whenever something feels slow. "About a second" and "about ten seconds"
  are different bugs.
- Keep a friction log. Anything you had to ask about is a finding, even if it worked.

## Prerequisites (each Mac)

1. macOS 26.3 or newer, Xcode installed.
2. Clone the repo, open `notchboard.xcodeproj`, build and run the `notchboard` scheme.
3. Grant Accessibility when asked (System Settings → Privacy & Security → Accessibility).
   On a managed SQLI Mac this may need an IT exception — if the toggle won't stick,
   that's finding number one.
4. Walk onboarding. Use your real first name — it labels your activity for the others.
   Pick "start with sample data" (host) or "start empty" (joiners — you'll adopt the
   host's catalogue anyway).
5. Optional but good: a booted iOS Simulator, to test docking alongside sync.

## Broker for this round

Use the public EMQX test broker — TLS, no account needed:

```
mqtts://broker.emqx.io:8883
```

Pick a room name nobody else on a public broker would guess, with a random suffix, for
example `sqli-mob-x7k2q`. The host generates the room password with the Generate button
and shares it over a separate channel (Slack DM is fine — never in the same message as
the exported file).

Brokers with their own account (HiveMQ Cloud, a hardened company mosquitto) work too,
and only the HOST ever deals with that: put the account username and password in the two
broker fields of the room dialog, once. For HiveMQ Cloud, create the credentials under
Access Management first and use the TLS MQTT URL as
`mqtts://<broker-id>.s1.eu.hivemq.cloud:8883`. The credential travels inside the invite,
sealed under the room password — joiners never see a broker field and never type it.

---

## Test cases

Record each as pass / fail / confused (confused counts — it means the UI didn't explain
itself). Expected timings assume a normal connection.

### Setup and joining

**T1 — host creates the room**
Host: collection ▾ menu (next to the collection name in the panel header) → "set up team
room…" → enter the broker address, room name, Generate a password → Join Room.
Expected: a "joining…" toast, then within a few seconds a "room connected · 1 online"
toast, the small square in the header turns green, and the menu item now reads
"room: <name> · connected".

**T2 — the invite is one line**
Host: collection ▾ menu → "copy room invite" → paste it into Slack. Share the room
password in a separate message.
Expected: one `notchboard-room:…` line, no file. It contains no readable secrets (it's
base64 — decode it if you're curious: broker address and room name are there, the broker
credential is ciphertext, the room password is nowhere).

**T3 — joiner pastes and joins**
Joiner: collection ▾ menu → "join with an invite…" → paste the line → type the room
password → Join. (A brand-new user can do the same during onboarding via the
"join a team room" starting point.) Count what you typed: it should be exactly one
password, even on a broker that requires an account.
Expected: a toast saying you joined and adopted the room's catalogue (your local copy was
snapshotted first), the dot turns green, and your panel now shows exactly the host's
groups and elements — including secret values, revealed by the eye icon.

**T4 — presence**
Both: look at the header.
Expected: "2 online" on both Macs, within a couple of seconds of T3 finishing.

### Live sync

**T5 — an edit travels**
Host: open any element → edit → change the note → save. Joiner: watch the same element.
Expected: the change appears on the joiner's Mac in about a second, without touching
anything. Then do the same in the other direction.

**T6 — a new element travels**
Joiner: ⌃N, create an element with a secret field filled in.
Expected: it appears on the host's Mac, secret value included.

**T7 — schema and structure travel**
Host: create a new group with two fields, then rename the collection.
Expected: joiners get the new group tab and the new collection name. Then host deletes
the group: it disappears everywhere.

### In-use marks and presence

**T8 — marking in use is attributed**
Joiner: click an element's use + copy button.
Expected: on the host's Mac the row shows "in use by <joiner's first name>" within about
a second — the real name, not an id string.

**T9 — notify when free**
Host: hover the in-use badge on that element → "notify when free". Joiner: release it.
Expected: the host gets a macOS notification and a toast that it's free, and the badge
clears everywhere.

**T10 — login on sim marks for everyone** *(needs a booted Simulator with the NotchDemo
sample installed on one Mac)*
One person: set the deeplink scheme (▾ menu) and hit login on sim on a free auth element.
Expected: the login fires locally AND the element shows in use on the other Macs.

### Disconnection — the interesting part

**T11 — an offline holder's mark renders free**
Joiner: mark an element in use, then turn wi-fi off. Host: watch that element and the
header.
Expected: within roughly a minute (the keepalive window) the host's header drops to
"1 online" and the element's status gains "· offline". The mark itself is still there —
it is presented as takeable, not deleted. The use button now reads "use + copy
(<name> offline)". Click it: you take the element over, with a toast saying why.

**T12 — the closed lid**
Joiner: wi-fi back on, wait for green, mark something in use, then just close the lid.
Expected: same as T11 on the host's side, within a minute or two. This is the case the
whole presence design exists for.

**T13 — reconnect catches up**
While the joiner is offline (T11 or T12): host edits one element, creates another, and
deletes a third. Joiner: reconnect (wi-fi on / lid open).
Expected: within a few seconds of the dot going green, the joiner has the edit and the
new element, and the deleted one is gone — not resurrected, even though the joiner's Mac
still had a copy. This is the single most important case in the plan. If a deleted
element comes back from the dead anywhere, stop and write down exactly what you did.

**T14 — offline work pushes back**
Joiner: while offline, edit one element and delete another. Reconnect.
Expected: the host receives both — the edit and the deletion — shortly after the
joiner's dot goes green.

**T15 — simultaneous edits pick one winner**
Both: open the same element and edit the same field to different values, saving as close
to simultaneously as you can manage.
Expected: within a couple of seconds both Macs show the SAME value (whichever save was
later). Losing one of the two edits is by design — showing different values on different
Macs is the bug.

### Safety rails

**T16 — wrong room password fails closed**
Third person (or a joiner after leaving, see T18): join the room with a deliberately
wrong password.
Expected: a loud "wrong room password" toast, a red dot, and — critically — your local
catalogue completely untouched. Nothing imported, nothing deleted.

**T17 — the same file twice doesn't double the catalogue**
Third person: import the same `.notchboard` file and join with the correct password.
Expected: they get exactly one copy of every element (same count as everyone else), and
nobody else's catalogue grows. "3 online" everywhere.

**T18 — leaving is clean**
One joiner: ▾ menu → "leave room…" → confirm.
Expected: the dot returns to amber, the collection keeps everything it had, edits made by
others no longer arrive, and the others' headers drop by one. Rejoining later via the
▾ menu asks for the password again (it was removed from the Keychain).

**T19 — quit and relaunch**
Host: quit Notchboard entirely, relaunch.
Expected: the room reconnects on its own (no password prompt — the Keychain has it), the
dot goes green, and anything that happened while quit arrives. Others saw the host go
offline at quit and come back at relaunch.

---

## Results

| # | Result (pass / fail / confused) | Timing felt | Notes |
|---|---|---|---|
| T1 | | | |
| T2 | | | |
| T3 | | | |
| T4 | | | |
| T5 | | | |
| T6 | | | |
| T7 | | | |
| T8 | | | |
| T9 | | | |
| T10 | | | |
| T11 | | | |
| T12 | | | |
| T13 | | | |
| T14 | | | |
| T15 | | | |
| T16 | | | |
| T17 | | | |
| T18 | | | |
| T19 | | | |

## Known and accepted for this round — don't file these

- If you release an element while offline, reconnecting brings your own old mark back
  for a while — it ages out via auto-release. A status light, not a document.
- Removing someone from the room means changing the room password and re-sharing it.
  There is no server to revoke anyone from — that's the §14.6 backend trigger, not a bug.
- A simultaneous same-field edit loses one side (T15). Different-element edits never
  conflict.
- The favourite star and your watch list are personal — they deliberately don't sync.

## What to send back

The results table, the friction log, and the answer to one question each: would you use
this instead of the Slack pinned message, and what's the first thing that would stop you?
