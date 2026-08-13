# About AI usage

Using an AI coding assistant on this project is encouraged, not merely tolerated. Large parts of
Notchboard were built with one, and [CLAUDE.md](CLAUDE.md) exists precisely so an agent arrives
knowing which decisions are load-bearing. Pretending otherwise in the contribution guide would be
dishonest.

Bug fixes are where it helps most. A bug comes with a reproduction and a failing test, so the output
is checkable against something concrete rather than against taste. Point the agent at the failing
test, let it work, and you have a fix you can verify in a minute.

Two conditions, and they are the whole policy.

## It has to match the vision

[vision.md](vision.md) is the product specification, and section 13 is the running log of what was
tried, what was measured and what was abandoned. An assistant that has not read it will confidently
rebuild something that was already removed for a reason, or add a feature the project decided
against.

Read [ROADMAP.md](ROADMAP.md) too before proposing anything large. Several of the obvious ideas are
listed there as deliberately not planned, with the reasoning attached.

If a change genuinely argues against something in vision.md, that is a conversation worth having in
an issue. Open one. What does not work is a pull request that quietly contradicts a documented
decision, because the review then has to reconstruct an argument nobody made.

## You have to read what it wrote

Every line, before the pull request exists. You are the author of that code, and review comments come
to you.

This is not a formality here. An assistant that has not internalised [CLAUDE.md](CLAUDE.md) will
cheerfully do any of the following, all of which look correct and all of which break something that
was expensive to learn:

- Re-enable the App Sandbox, which silently breaks docking with no error and no permission dialog.
- Write tests in XCTest, or gate a test with `try #require` instead of a suite-level `.enabled(if:)`
  trait. The second turns a clean clone's first test run red.
- Add a `repeatForever` animation to the panel, which costs about 20% of a CPU core for as long as
  the panel is open.
- Add a migration shim, a `v2` identifier or a compatibility path, none of which this project has or
  wants before its first release.
- Make the panel activating, or swap the Carbon hot-key registration for an `NSEvent` monitor, which
  cannot consume a keystroke and so double-triggers Xcode's own shortcuts.
- Write "claim" into user-facing copy, or put a trailing ellipsis on an action label.

Each of those has a bug behind it, recorded in CLAUDE.md or vision.md section 13. The file is written
for exactly this reason, so give it to your assistant at the start rather than after the review.

## Before you open the pull request

The same checks as any other contribution, in [CONTRIBUTING.md](CONTRIBUTING.md). Run the build and
the full test suite yourself rather than taking the assistant's word for it, and boot a broker and a
simulator if you touched sync or the deeplink bridge, since those suites skip silently otherwise.

Mentioning that you used an assistant is welcome and never counts against a pull request. It is not
required, and nobody will go looking.
