# Third-party notices

Notchboard itself is licensed under the Apache License 2.0. See [LICENSE](LICENSE).

This file lists everything else that ends up inside a built copy of the app. If you attach a
built `.app` to a release, ship this file alongside it. Apache-2.0 section 4 asks for the licence
to accompany any distribution in object form, and every dependency below is Apache-2.0.

## Swift packages

Resolved versions come from `notchboard.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`,
which is committed, so a clone builds against exactly these.

| Package | Version | Licence | Source |
| --- | --- | --- | --- |
| mqtt-nio | 2.13.0 | Apache-2.0 | https://github.com/swift-server-community/mqtt-nio |
| swift-atomics | 1.3.1 | Apache-2.0 | https://github.com/apple/swift-atomics |
| swift-collections | 1.6.0 | Apache-2.0 | https://github.com/apple/swift-collections |
| swift-log | 1.15.0 | Apache-2.0 | https://github.com/apple/swift-log |
| swift-nio | 2.101.3 | Apache-2.0 | https://github.com/apple/swift-nio |
| swift-nio-ssl | 2.37.2 | Apache-2.0 | https://github.com/apple/swift-nio-ssl |
| swift-nio-transport-services | 1.28.0 | Apache-2.0 | https://github.com/apple/swift-nio-transport-services |
| swift-system | 1.8.0 | Apache-2.0 | https://github.com/apple/swift-system |

Only mqtt-nio is a direct dependency. The rest arrive through it.

## Fonts

Both typefaces are bundled in the app under the SIL Open Font License 1.1, which permits
redistribution as part of a larger work. The full licence text for each sits next to the font
files in `notchboard/Fonts/` and ships inside the app bundle.

| Typeface | Weights bundled | Licence | Source |
| --- | --- | --- | --- |
| Space Grotesk | Regular, Medium, Bold | OFL-1.1 | https://github.com/floriankarsten/space-grotesk |
| JetBrains Mono | Regular, Medium, Bold | OFL-1.1 | https://github.com/JetBrains/JetBrainsMono |

Copyright 2020 The Space Grotesk Project Authors. Copyright 2020 The JetBrains Mono Project
Authors. Neither font is used as a reserved-name variant, and neither is sold on its own, so the
OFL's two substantive conditions are satisfied by shipping the licence text above.
