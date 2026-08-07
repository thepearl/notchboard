//
//  SnapshotAndPassphraseTests.swift
//  notchboardTests
//
//  Local snapshots (vision.md §14.5.2) and the passphrase generator (§14.5.3). Snapshot
//  tests point the store at a scratch directory and run serialized, because directoryURL
//  is shared static state. The device key they exercise is the real Keychain item — a
//  single stable entry under flourix.notchboard.device, harmless on a dev machine.
//

import AppKit
import Foundation
import Testing
@testable import notchboard

@Suite("Snapshots", .serialized)
struct SnapshotStoreTests {

    private func useScratchDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nb-snapshot-tests-\(UUID().uuidString)", isDirectory: true)
        SnapshotStore.directoryURL = url
        return url
    }

    @Test("A snapshot round-trips through the device key")
    func roundTrip() throws {
        let dir = useScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let collection = NBCollection(workspace: MockData.emptyWorkspace(name: "snap"))
        SnapshotStore.recordIfDue(collections: [collection], activeCollectionID: collection.id, force: true)

        let url = try #require(SnapshotStore.list().first, "the forced snapshot must exist")
        let payload = try SnapshotStore.load(from: url)
        #expect(payload.collections == [collection])
        #expect(payload.activeCollectionID == collection.id)
    }

    @Test("Rotation keeps only the newest maxSnapshots")
    func rotationBound() throws {
        let dir = useScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let collection = NBCollection(workspace: MockData.emptyWorkspace(name: "r"))
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<(SnapshotStore.maxSnapshots + 5) {
            SnapshotStore.recordIfDue(
                collections: [collection], activeCollectionID: collection.id,
                force: true, at: base.addingTimeInterval(TimeInterval(index * 60))
            )
        }
        #expect(SnapshotStore.list().count == SnapshotStore.maxSnapshots)
    }

    @Test("The interval gate turns per-save calls into periodic snapshots")
    func intervalGate() throws {
        let dir = useScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let collection = NBCollection(workspace: MockData.emptyWorkspace(name: "g"))
        SnapshotStore.recordIfDue(collections: [collection], activeCollectionID: collection.id)
        SnapshotStore.recordIfDue(collections: [collection], activeCollectionID: collection.id)
        #expect(SnapshotStore.list().count == 1, "back-to-back saves must coalesce into one snapshot")
    }

    @Test("A snapshot from any other format version is refused", arguments: [0, 2, 99])
    func otherVersionsRefused(version: Int) {
        // Same exact-match rule as imports (vision.md §14.5): the realistic mismatch is a
        // future build's snapshot on the same Mac, and pre-release the answer is refusal.
        var payload = SnapshotPayload(collections: [], activeCollectionID: "")
        payload.formatVersion = version
        #expect(throws: SnapshotStore.SnapshotError.unsupportedVersion(version)) {
            try SnapshotStore.validatePayloadVersion(payload)
        }
    }

    @Test("Snapshots are never plaintext on disk")
    func encryptedAtRest() throws {
        let dir = useScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let marker = "super-plain-secret-value-93cd"
        var workspace = MockData.emptyWorkspace(name: "e")
        if var group = workspace.groups["users"] {
            group.elements.append(NBElement(
                id: "snap-el", name: "acct", environments: [.dev], isFavorite: false, claimedBy: nil,
                note: "", lastUsed: "", values: ["username": "u", "password": marker]
            ))
            workspace.groups["users"] = group
        }
        let collection = NBCollection(workspace: workspace)
        SnapshotStore.recordIfDue(collections: [collection], activeCollectionID: collection.id, force: true)

        let url = try #require(SnapshotStore.list().first)
        let bytes = try Data(contentsOf: url)
        #expect(!String(decoding: bytes, as: UTF8.self).contains(marker))
    }
}

@Suite("Password prompt layout")
struct PromptAccessoryTests {

    // The regression this exists for: the export prompt's field and Generate button were
    // arranged with an NSStackView, which lays out with Auto Layout — an empty NSTextField
    // has a near-zero intrinsic width, so the field collapsed to a sliver and the password
    // was invisible. Forcing layout here is the point: a frame set at construction proves
    // nothing, surviving layout does.

    @Test("The export field keeps a usable width after layout")
    func exportFieldSurvivesLayout() {
        let field = PromptAccessory.makeField(NSTextField(), placeholder: "export password")
        let generate = NSButton(title: "Generate", target: nil, action: nil)
        let container = PromptAccessory.passwordWithGenerate(field: field, generate: generate)
        container.layoutSubtreeIfNeeded()

        #expect(field.frame.width >= 200, "a generated passphrase must be readable in the field")
        #expect(field.frame.height >= 20)
        #expect(generate.frame.maxX <= container.frame.width, "Generate must stay inside the accessory view")
        #expect(field.frame.maxX <= generate.frame.minX, "the field and the button must not overlap")
    }

    @Test("The import field keeps a usable width after layout")
    func importFieldSurvivesLayout() {
        let field = PromptAccessory.makeField(NSSecureTextField(), placeholder: "password")
        let container = PromptAccessory.password(field: field)
        container.layoutSubtreeIfNeeded()
        #expect(field.frame.width >= 200)
    }

    @Test("Prompt fields are single-line and non-wrapping")
    func fieldsAreSingleLine() {
        let field = PromptAccessory.makeField(NSTextField(), placeholder: "p")
        #expect(field.usesSingleLineMode)
        #expect(field.cell?.wraps == false)
    }
}

@Suite("Passphrase generator")
struct PassphraseGeneratorTests {

    @Test("Four dash-separated groups of five, from the unambiguous alphabet")
    func format() {
        for _ in 0..<50 {
            let passphrase = PassphraseGenerator.generate()
            let groups = passphrase.split(separator: "-")
            #expect(groups.count == 4)
            #expect(groups.allSatisfy { $0.count == 5 })
            #expect(!passphrase.contains { "ilo01".contains($0) }, "ambiguous symbols would make passphrases mis-transcribable")
        }
    }

    @Test("Generations don't collide")
    func unique() {
        let all = (0..<200).map { _ in PassphraseGenerator.generate() }
        #expect(Set(all).count == all.count)
    }
}
