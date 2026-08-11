//
//  BundledFontTests.swift
//  notchboardTests
//
//  Guards the typography actually reaching the screen.
//
//  Before the fonts were bundled, NBFont asked for "Space Grotesk" and "JetBrains Mono" by name
//  and silently got the system font on any machine without them installed — including the
//  author's, which had no Space Grotesk at all. Nothing failed, nothing warned, the app just
//  never looked like its own design system. These tests fail loudly instead.
//

import AppKit
import Testing
@testable import notchboard

@Suite("Bundled typography")
@MainActor
struct BundledFontTests {

    /// The test target is hosted by the app, so `Bundle.main` here is the built app bundle —
    /// exactly what a user would run.
    private var bundledFontFiles: Set<String> {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
        return Set(urls.map(\.lastPathComponent))
    }

    @Test("Both typefaces ship inside the app bundle")
    func fontFilesAreBundled() {
        let files = bundledFontFiles
        #expect(files.contains("SpaceGrotesk-Regular.ttf"), "bundled ttf files: \(files.sorted())")
        #expect(files.contains("JetBrainsMono-Regular.ttf"), "bundled ttf files: \(files.sorted())")
    }

    @Test("Registration makes both families resolvable under the names NBFont asks for")
    func familiesResolve() {
        NBBundledFonts.register()
        #expect(
            NSFont(name: NBBundledFonts.uiFamily, size: 12) != nil,
            "\(NBBundledFonts.uiFamily) did not register — every UI label would fall back to the system font"
        )
        #expect(
            NSFont(name: NBBundledFonts.monoFamily, size: 12) != nil,
            "\(NBBundledFonts.monoFamily) did not register — every value and badge would fall back"
        )
    }

    /// A family with one face makes `.weight(.bold)` a synthesised smear rather than the real
    /// cut. Three faces (regular, medium, bold) is what the call sites in the app need.
    @Test("Each family exposes its real weights, not one face the renderer has to fake")
    func weightsAreRealFaces() {
        NBBundledFonts.register()
        for family in [NBBundledFonts.uiFamily, NBBundledFonts.monoFamily] {
            let members = NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []
            #expect(members.count >= 3, "\(family) exposes \(members.count) face(s), expected regular/medium/bold")
        }
    }

    /// The OFL requires the licence to travel with the font. Both texts sit next to the files
    /// they cover, so they ship in the same bundle.
    @Test("Each bundled typeface carries its OFL licence")
    func licencesTravelWithTheFonts() {
        let texts = Set((Bundle.main.urls(forResourcesWithExtension: "txt", subdirectory: nil) ?? [])
            .map(\.lastPathComponent))
        #expect(texts.contains("SpaceGrotesk-OFL.txt"), "bundled txt files: \(texts.sorted())")
        #expect(texts.contains("JetBrainsMono-OFL.txt"), "bundled txt files: \(texts.sorted())")
    }
}
