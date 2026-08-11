//
//  NBBundledFonts.swift
//  notchboard
//
//  Registers the design system's two typefaces out of the app bundle.
//
//  Notchboard is distributed as source, so it cannot assume Space Grotesk or JetBrains Mono are
//  installed on the machine that builds it. Neither was installed on the author's Mac either,
//  which is why every screenshot to date was really the system font wearing the design system's
//  sizes — the locked visual direction in vision.md §7 never actually rendered. Shipping the
//  files is what makes NBFont mean the same thing on a stranger's machine.
//
//  Registration is programmatic rather than Info.plist's ATSApplicationFontsPath because the app
//  target is a synchronized folder group: Xcode flattens Fonts/ into Contents/Resources, so the
//  subfolder that key would have to name does not survive the build. Looking the files up by
//  extension works whichever way Xcode lays them out.
//
//  Only the weights the app actually asks for are bundled (regular/medium/bold for both, plus
//  Space Grotesk Bold for the 15 .bold call sites). Space Grotesk publishes no SemiBold, so the
//  five .semibold sites resolve to the nearest weight, which is the intended fallback rather
//  than a missing font.
//

import CoreText
import Foundation

enum NBBundledFonts {
    /// The family names the app asks for. These are the OpenType *typographic* families, which
    /// is what groups Regular, Medium and Bold into one family that `.weight()` can select
    /// within — the per-file legacy names ("Space Grotesk Medium") deliberately differ.
    static let uiFamily = "Space Grotesk"
    static let monoFamily = "JetBrains Mono"

    /// Safe to call from anywhere, as often as you like. The work happens once.
    static func register() { _ = registered }

    /// `.process` scope, never `.persistent`: these belong to this run of this app and must not
    /// end up in the user's Font Book.
    private static let registered: Void = {
        let bundle = Bundle.main
        let urls = (bundle.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (bundle.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
        for url in Set(urls) {
            var error: Unmanaged<CFError>?
            // A refusal is not fatal. SwiftUI's `.custom` falls back to the system font, so the
            // app stays legible rather than blank on a machine that won't register these.
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }()
}
