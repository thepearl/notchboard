# Third-party notices

Notchboard itself is licensed under the Apache License 2.0. See [LICENSE](LICENSE).

This file lists everything else that ends up inside a built copy of the app. Apache-2.0 section 4
asks for the licence to accompany any distribution in object form, and the MIT, BSD and zlib
notices below have to travel with binaries too, so the release job attaches this file to every
GitHub release next to the zip. If you distribute a built `.app` yourself, ship it alongside.

## Swift packages

Resolved versions come from `notchboard.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`,
which is committed, so a clone builds against exactly these.

| Package | Version | Licence | Source |
| --- | --- | --- | --- |
| mqtt-nio | 2.13.0 | Apache-2.0 | https://github.com/swift-server-community/mqtt-nio |
| Sparkle | 2.9.6 | MIT, with BSD-2-Clause, MIT and zlib components (below) | https://github.com/sparkle-project/Sparkle |
| swift-atomics | 1.3.1 | Apache-2.0 | https://github.com/apple/swift-atomics |
| swift-collections | 1.6.0 | Apache-2.0 | https://github.com/apple/swift-collections |
| swift-log | 1.15.0 | Apache-2.0 | https://github.com/apple/swift-log |
| swift-nio | 2.101.3 | Apache-2.0 | https://github.com/apple/swift-nio |
| swift-nio-ssl | 2.37.2 | Apache-2.0 | https://github.com/apple/swift-nio-ssl |
| swift-nio-transport-services | 1.28.0 | Apache-2.0 | https://github.com/apple/swift-nio-transport-services |
| swift-system | 1.8.0 | Apache-2.0 | https://github.com/apple/swift-system |

mqtt-nio and Sparkle are direct dependencies. The rest arrive through mqtt-nio. Sparkle is a
prebuilt binary framework fetched from its GitHub release (checksum pinned in `Package.resolved`)
and embedded at `Contents/Frameworks/Sparkle.framework`.

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

## Sparkle

Sparkle's `LICENSE` file, reproduced verbatim. The framework itself is MIT. The four component
notices that follow it cover bsdiff and bspatch (BSD-2-Clause, Colin Percival), sais-lite (MIT,
Yuta Mori), the portable Ed25519 implementation (zlib licence, Orson Peters) and
`SUSignatureVerifier.m` (BSD-2-Clause, Mark Hamlin).

```text
Copyright (c) 2006-2013 Andy Matuschak.
Copyright (c) 2009-2013 Elgato Systems GmbH.
Copyright (c) 2011-2014 Kornel Lesiński.
Copyright (c) 2015-2017 Mayur Pawashe.
Copyright (c) 2014 C.W. Betts.
Copyright (c) 2014 Petroules Corporation.
Copyright (c) 2014 Big Nerd Ranch.
All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=================
EXTERNAL LICENSES
=================

bspatch.c and bsdiff.c, from bsdiff 4.3 <http://www.daemonology.net/bsdiff/>:

Copyright 2003-2005 Colin Percival
All rights reserved

Redistribution and use in source and binary forms, with or without
modification, are permitted providing that the following conditions 
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

--

sais.c and sais.h, from sais-lite (2010/08/07) <https://sites.google.com/site/yuta256/sais>:

The sais-lite copyright is as follows:

Copyright (c) 2008-2010 Yuta Mori All Rights Reserved.

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

--

Portable C implementation of Ed25519, from https://github.com/orlp/ed25519

Copyright (c) 2015 Orson Peters <orsonpeters@gmail.com>

This software is provided 'as-is', without any express or implied warranty. In no event will the
authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial
applications, and to alter it and redistribute it freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the
   original software. If you use this software in a product, an acknowledgment in the product
   documentation would be appreciated but is not required.

2. Altered source versions must be plainly marked as such, and must not be misrepresented as
   being the original software.

3. This notice may not be removed or altered from any source distribution.

--

SUSignatureVerifier.m:

Copyright (c) 2011 Mark Hamlin.

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted providing that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
```
