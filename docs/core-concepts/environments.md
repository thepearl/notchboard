---
icon: layer-group
description: Why an element carries a set of environments rather than one.
---

# Environments

An element carries a set of environments, not a single value. `DEV`, `STG` and `PRD`, in that display order.

## Why a set

The same test account usually exists in more than one place, seeded into dev and staging with identical credentials. Forcing a single choice made people duplicate the row, and then one copy drifted.

A set removes the reason to duplicate.

## Filtering

Four chips sit at the top of the list, `ALL`, `DEV`, `STG` and `PRD`, single-select.

`ALL` is a filter only. It is never assignable to an element, so an element always names the environments it actually exists in.

## The production warning

Tick `PRD` alongside anything else and Notchboard asks once, at save time, whether you meant it.

A production credential reachable from a dev build is how production data ends up in a staging log. The dialog has a "Never show this warning again" checkbox, and the same switch lives in Settings as "Warn before mixing production with another environment".

{% hint style="warning" %}
That warning is the whole mechanism. There is no policy engine behind it, and Notchboard is not a production secrets store.
{% endhint %}

## What travels

Environments sync to a team room with the rest of an element's content, and they are readable plaintext in an export file. They are metadata about where an account lives, not a secret in their own right.
