---
icon: scale-balanced
description: Apache-2.0, plus every third-party component inside a built copy of the app.
---

# Licence

Notchboard is licensed under the Apache License 2.0. The full text is in `LICENSE` at the root of the repository.

{% hint style="info" %}
Apache-2.0 section 4 asks for the licence to accompany any distribution in object form. If you attach a built `.app` to a release, ship `THIRD-PARTY-NOTICES.md` alongside it.
{% endhint %}

## Swift packages

Resolved versions come from `Package.resolved`, which is committed, so a clone builds against exactly these. Only mqtt-nio is a direct dependency, and the rest arrive through it.

| Package                      | Version | Licence    | Source                                                                                      |
| ---------------------------- | ------- | ---------- | ------------------------------------------------------------------------------------------- |
| mqtt-nio                     | 2.13.0  | Apache-2.0 | [swift-server-community/mqtt-nio](https://github.com/swift-server-community/mqtt-nio)       |
| swift-atomics                | 1.3.1   | Apache-2.0 | [apple/swift-atomics](https://github.com/apple/swift-atomics)                               |
| swift-collections            | 1.6.0   | Apache-2.0 | [apple/swift-collections](https://github.com/apple/swift-collections)                       |
| swift-log                    | 1.15.0  | Apache-2.0 | [apple/swift-log](https://github.com/apple/swift-log)                                       |
| swift-nio                    | 2.101.3 | Apache-2.0 | [apple/swift-nio](https://github.com/apple/swift-nio)                                       |
| swift-nio-ssl                | 2.37.2  | Apache-2.0 | [apple/swift-nio-ssl](https://github.com/apple/swift-nio-ssl)                               |
| swift-nio-transport-services | 1.28.0  | Apache-2.0 | [apple/swift-nio-transport-services](https://github.com/apple/swift-nio-transport-services) |
| swift-system                 | 1.8.0   | Apache-2.0 | [apple/swift-system](https://github.com/apple/swift-system)                                 |

## Fonts

Both typefaces are bundled in the app under the SIL Open Font License 1.1, which permits redistribution as part of a larger work. The full licence text for each sits next to the font files in `notchboard/Fonts/` and ships inside the app bundle.

| Typeface       | Weights bundled       | Licence | Source                                                                          |
| -------------- | --------------------- | ------- | ------------------------------------------------------------------------------- |
| Space Grotesk  | Regular, Medium, Bold | OFL-1.1 | [floriankarsten/space-grotesk](https://github.com/floriankarsten/space-grotesk) |
| JetBrains Mono | Regular, Medium, Bold | OFL-1.1 | [JetBrains/JetBrainsMono](https://github.com/JetBrains/JetBrainsMono)           |

Copyright 2020 The Space Grotesk Project Authors. Copyright 2020 The JetBrains Mono Project Authors.

Neither font is used as a reserved-name variant, and neither is sold on its own, so the OFL's two substantive conditions are satisfied by shipping the licence text.

{% hint style="info" %}
The fonts are registered at runtime rather than through `ATSApplicationFontsPath`, so there is nothing to install on your machine.
{% endhint %}
