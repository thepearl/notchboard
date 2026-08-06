//
//  IdleAnimationGuardTests.swift
//  notchboardTests
//
//  Guards the panel's idle cost. The panel is a transparent borderless window, so every
//  animation frame makes the window server re-blend the whole panel (and its 70pt drop
//  shadow) against the desktop: one continuously pulsing 6pt dot measured at ~20% of a
//  CPU core for as long as the panel was open, against 0.1% with nothing animating.
//
//  A unit test can't measure CPU reliably in CI, so this asserts the *structural* rule
//  instead: no `repeatForever` animation may sit in a view without an interaction gate
//  (hover/focus state) deciding whether it runs. Source-scanning is crude, but it fails
//  loudly the moment someone reintroduces an always-on animation, which is exactly the
//  regression that is otherwise invisible until a user notices their fans.
//

import Foundation
import Testing

@Suite("Idle animation guard")
struct IdleAnimationGuardTests {

    /// Walks up from this file to the repo root, then enumerates the app's Swift sources.
    private func appSourceFiles() throws -> [URL] {
        var root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // notchboardTests
            .deletingLastPathComponent() // repo root
        root.appendPathComponent("notchboard", isDirectory: true)

        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    @Test("No repeatForever animation runs without an interaction gate")
    func noUngatedRepeatForever() throws {
        let files = try appSourceFiles()
        try #require(!files.isEmpty, "could not locate app sources — fix the path logic, don't skip the check")

        var offenders: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            guard source.contains("repeatForever") else { continue }
            // The gate: the same view must consult a hover/interaction flag, so the
            // animation only runs while the user is engaging with it.
            let isGated = source.contains("isHovering") || source.contains("hovering")
            if !isGated {
                offenders.append(file.lastPathComponent)
            }
        }

        #expect(
            offenders.isEmpty,
            """
            Ungated repeatForever animation in: \(offenders.joined(separator: ", ")).
            Continuous animation in the transparent panel costs ~20% of a CPU core while \
            the panel is open. Gate it behind hover/interaction state.
            """
        )
    }

    /// `.buttonStyle(.plain)` hit-tests only the pixels the label draws, so a Text inside a
    /// frame with a stroked border is clickable on its glyphs alone. Every button in the app
    /// had that bug; `.nbPlain` fixes it centrally. This keeps `.plain` from creeping back.
    @Test("No button uses .plain instead of .nbPlain")
    func noPlainButtonStyle() throws {
        let offenders = try appSourceFiles().filter { file in
            try String(contentsOf: file, encoding: .utf8).contains("buttonStyle(.plain)")
        }.map(\.lastPathComponent)

        #expect(
            offenders.isEmpty,
            """
            .buttonStyle(.plain) in: \(offenders.joined(separator: ", ")).
            Use .buttonStyle(.nbPlain) — .plain leaves the button clickable only on the \
            label's drawn glyphs, not the box the user sees.
            """
        )
    }

    @Test("The claim badge does not animate a shadow radius")
    func noAnimatedShadowRadius() throws {
        let row = try appSourceFiles().first { $0.lastPathComponent == "ElementRowView.swift" }
        let source = try String(contentsOf: try #require(row), encoding: .utf8)
        // `radius: pulse ? 6 : 3` re-rasterises the shadow every frame — measurably worse
        // than animating opacity, which the compositor handles.
        #expect(!source.contains("radius: pulse"), "animate opacity, not a shadow radius")
    }
}
