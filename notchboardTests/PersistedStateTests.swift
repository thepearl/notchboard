//
//  PersistedStateTests.swift
//  notchboardTests
//
//  The persisted-state contract, pre-release edition: `collections` + `activeCollectionID`
//  + `memberID`, decoded strictly for the catalogue and leniently for settings. There is
//  deliberately NO migration or downgrade machinery to test (vision.md §14.5): a file in
//  any other shape refuses to decode and takes load()'s corrupt-backup reset path.
//

import Foundation
import Testing
@testable import notchboard

@Suite("Persisted state")
struct PersistedStateTests {

    @Test("A pre-collections file refuses to decode — the reset path, by design")
    func oldShapeRefused() {
        // The shape of a pre-collections state.json: a bare `workspace` and a global
        // scheme. No compat code exists for it, so decode must throw and load() moves the
        // file to state.json.corrupt.
        let old = Data("""
        {"schemaVersion":1,"deeplinkScheme":"notchdemo","onboardingCompleted":true,\
        "workspace":{"name":"my-catalogue","groupOrder":[],"groups":{},"members":{}}}
        """.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(PersistedAppState.self, from: old)
        }
    }

    @Test("A state file stamped with any other schema version is refused")
    func otherSchemaVersionRefused() throws {
        let a = NBCollection(workspace: MockData.emptyWorkspace(name: "a"))
        let stamped = Data("""
        {"schemaVersion":99,"collections":\(String(decoding: try JSONEncoder().encode([a]), as: UTF8.self))}
        """.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(PersistedAppState.self, from: stamped)
        }
    }

    @Test("An empty collections array is refused, not tolerated")
    func emptyCollectionsRefused() {
        let empty = Data(#"{"collections":[],"onboardingCompleted":true}"#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(PersistedAppState.self, from: empty)
        }
    }

    @Test("Encode/decode round trip carries the properties and nothing else")
    func roundTripIsExactlyTheProperties() throws {
        let a = NBCollection(deeplinkScheme: "brewly", workspace: MockData.emptyWorkspace(name: "a"))
        let b = NBCollection(deeplinkScheme: "other", workspace: MockData.emptyWorkspace(name: "b"))
        let state = PersistedAppState(
            collections: [a, b], activeCollectionID: b.id, memberID: "m",
            autoReleaseMinutes: 60, startExpanded: true, dockEdge: .right,
            onboardingCompleted: true, onboardingName: "x"
        )
        let data = try JSONEncoder().encode(state)

        let round = try JSONDecoder().decode(PersistedAppState.self, from: data)
        #expect(round.collections.count == 2)
        #expect(round.activeCollectionID == b.id)
        #expect(round.memberID == "m")

        // Nothing beyond the properties: no shadow copies, no duplicate shapes. This pins
        // the no-compat rule at the wire level.
        let raw = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(raw["workspace"] == nil)
        #expect(raw["deeplinkScheme"] == nil)
    }

    @Test("A stale activeCollectionID falls back to the first collection")
    func staleActiveID() throws {
        let a = NBCollection(workspace: MockData.emptyWorkspace(name: "a"))
        var state = PersistedAppState(
            collections: [a], activeCollectionID: a.id, memberID: "m",
            autoReleaseMinutes: 60, startExpanded: true, dockEdge: .right,
            onboardingCompleted: true, onboardingName: "x"
        )
        state.activeCollectionID = "ghost-id"
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PersistedAppState.self, from: data)
        #expect(decoded.activeCollectionID == a.id)
    }

    @Test("Settings stay lenient: a state file missing every setting still loads")
    func settingsLenient() throws {
        let a = NBCollection(workspace: MockData.emptyWorkspace(name: "a"))
        let minimal = Data("""
        {"collections":\(String(decoding: try JSONEncoder().encode([a]), as: UTF8.self))}
        """.utf8)
        let decoded = try JSONDecoder().decode(PersistedAppState.self, from: minimal)
        #expect(decoded.autoReleaseMinutes == 60)
        #expect(decoded.startExpanded)
        #expect(!decoded.memberID.isEmpty, "identity is generated when absent")
    }
}
