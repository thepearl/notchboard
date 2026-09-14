# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase. This repo is **single-context**: `vision.md` at the repo root is the product source of truth — the specification, a running implementation log (§13, "what's real vs still vision") and the design decisions (§14).

## Before exploring, read these

- **`vision.md`** at the repo root — start with the sections that touch the area you're about to work in (§13 is the implementation log, §14 the design decisions).

If `vision.md` is missing, **proceed silently**. Don't flag its absence; don't suggest creating it.

## Use the doc's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `vision.md`. Don't drift to synonyms the spec explicitly avoids.

If the concept you need isn't in the doc yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it).

## Flag conflicts

If your output contradicts a decision recorded in `vision.md`, surface it explicitly rather than silently overriding:

> _Contradicts the §14 decision on …, but worth reopening because…_
