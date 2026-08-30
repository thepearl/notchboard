# Security policy

Notchboard holds shared test credentials, so security reports take priority over everything else in the tracker.

## Reporting a vulnerability

Report privately, never in a public issue:

- Preferred: [GitHub private vulnerability reporting](https://github.com/thepearl/notchboard/security/advisories/new)
- Or email the maintainer at ghazi.tozri98@gmail.com

Include what you found, how to reproduce it, and what an attacker gains. You will get a first answer within a week. This is a solo-maintained project, so a fix may take longer than that, and you will be kept informed along the way.

## Scope

In scope: the app itself, the encrypted export format, the room invite format, and the sync protocol. The [security model](https://thepearl.github.io/notchboard/documentation/guides/security-model/) describes the guarantees, and the [integration reference](https://thepearl.github.io/notchboard/integration/) describes the formats.

Two exposures are accepted and documented rather than hidden: the deeplink password is briefly visible in the local process list while `simctl` runs, and an export file's non-secret fields are readable plaintext. Those are design decisions with their reasoning in the docs. Anything that breaks a stated guarantee (a secret readable without its password, room ciphertext the broker can decrypt, a way past the import trust boundary) very much is a vulnerability.

## Supported versions

Only the latest release is supported. There is no backporting.
