## What this changes

<!-- One or two sentences. Link the issue if there is one. -->

## How it was tested

```bash
xcodebuild -project notchboard.xcodeproj -scheme notchboard -destination 'platform=macOS' test
```

<!-- The room and deeplink suites skip themselves without a local mosquitto and a booted
     simulator. Say whether you ran with them or without (INSTALL.md shows how to boot both). -->

## Checklist

- [ ] Tests pass locally, and new behaviour comes with a test
- [ ] `swiftlint lint` adds no new warnings
- [ ] Commits follow `<type>: <description>` (feat, fix, refactor, docs, test, chore, perf, ci)
- [ ] Docs updated if behaviour changed (`docs/` feeds the published site, `vision.md` section 13 logs implementation decisions)
