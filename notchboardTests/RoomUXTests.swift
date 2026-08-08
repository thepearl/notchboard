//
//  RoomUXTests.swift
//  notchboardTests
//
//  The user-facing half of the room feature: the connection colour mapping, the
//  effectively-free rendering rule as the view model exposes it, the offline takeover,
//  the room address travelling in exports, the Keychain store, and the room dialogs'
//  accessory layout (the PromptAccessoryTests pattern — NSStackView once collapsed the
//  password field to a sliver, so layout is forced and measured, not assumed).
//

import AppKit
import CryptoKit
import Foundation
import SwiftUI
import Testing
@testable import notchboard

@Suite("Connection dot colour")
struct SyncStateColorTests {

    @Test("No room and in-between states stay amber; live is green; failure is red")
    func mapping() {
        #expect(NBColor.syncState(nil) == NBColor.amber, "a local collection keeps the brand square exactly as it was")
        #expect(NBColor.syncState(.connecting) == NBColor.amber)
        #expect(NBColor.syncState(.disconnected) == NBColor.amber)
        #expect(NBColor.syncState(.connected) == NBColor.green)
        #expect(NBColor.syncState(.failed("x")) == NBColor.red)
    }
}

@Suite("Effectively-free rendering and offline takeover", .serialized)
struct EffectivelyFreeTests {

    private let key = SymmetricKey(data: Data(repeating: 3, count: 32))
    private let config = NBRoomConfig(brokerURL: "mqtts://broker.test:8883", room: "ux")

    @MainActor
    private struct Room {
        let vm: NotchboardViewModel
        let peerStore: CollectionStore
        let peerTransport: LoopbackTransport
        let broker: LoopbackBroker
        /// Held so the sessions stay alive for the test's duration.
        let engines: [SyncEngine]
    }

    /// A view model wired to a live loopback room, plus a second peer to hold claims.
    @MainActor
    private func makeRoom() -> Room {
        SnapshotStore.directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nb-roomux-\(UUID().uuidString)", isDirectory: true)
        let broker = LoopbackBroker()

        let vm = NotchboardViewModel()
        vm.selfMemberID = "member-me"
        vm.store.selfMemberID = "member-me"
        let engine = SyncEngine(store: vm.store, selfMemberID: "member-me", selfName: "ghazi") { _, _ in
            broker.makeTransport()
        }
        vm.store.changeSink = { [weak engine] in engine?.handleLocalChange($0) }
        vm.syncEngine = engine
        engine.joinRoom(config, password: "", collectionID: vm.activeCollectionID, preDerivedKey: key)
        broker.pump() // empty room → the view model's catalogue seeds it

        // The peer, holding the engine alive via the returned tuple's stores.
        let peerCollection = NBCollection(workspace: NBWorkspace(name: "peer", groupOrder: [], groups: [:], members: [:]))
        let peerStore = CollectionStore(collections: [peerCollection])
        peerStore.selfMemberID = "member-peer"
        let peerEngine = SyncEngine(store: peerStore, selfMemberID: "member-peer", selfName: "lina") { _, _ in
            broker.makeTransport()
        }
        peerStore.changeSink = { [weak peerEngine] in peerEngine?.handleLocalChange($0) }
        peerEngine.joinRoom(config, password: "", collectionID: peerCollection.id, preDerivedKey: key)
        broker.pump()

        return Room(vm: vm, peerStore: peerStore, peerTransport: broker.lastTransport!,
                    broker: broker, engines: [engine, peerEngine])
    }

    @Test("The matrix: mine, theirs-online, theirs-offline, and roomless")
    func matrix() {
        let room = makeRoom()
        let (vm, peerStore, peerTransport, broker) = (room.vm, room.peerStore, room.peerTransport, room.broker)
        let element = vm.activeGroup.elements.first!

        // Free element: trivially free.
        #expect(vm.isEffectivelyFree(element))

        // Mine: never "effectively free" — it's yours, shown as yours.
        vm.claimOrRelease(element.id)
        #expect(!vm.isEffectivelyFree(vm.selectedElement(id: element.id)!))
        vm.claimOrRelease(element.id) // release again
        broker.pump()

        // Theirs, online: genuinely in use.
        peerStore.setClaim(NBClaim(who: "member-peer"), elementID: element.id,
                           group: peerStore.workspace.groupOrder[0],
                           collection: peerStore.activeCollectionID, claimantName: "lina")
        broker.pump()
        let claimed = vm.selectedElement(id: element.id)!
        #expect(claimed.claimedBy?.who == "member-peer")
        #expect(!vm.isEffectivelyFree(claimed))
        #expect(vm.presenceSuffix(for: claimed.claimedBy!).isEmpty)

        // Theirs, offline: renders free, mark untouched, suffix says why.
        broker.partition(peerTransport)
        broker.pump()
        let offlineHeld = vm.selectedElement(id: element.id)!
        #expect(vm.isEffectivelyFree(offlineHeld))
        #expect(offlineHeld.claimedBy?.who == "member-peer", "presence must never mutate the mark")
        #expect(vm.presenceSuffix(for: offlineHeld.claimedBy!) == " · offline")

        // Using it while they're offline is a deliberate takeover.
        vm.claimOrRelease(element.id)
        #expect(vm.selectedElement(id: element.id)?.claimedBy?.who == "member-me")
        withExtendedLifetime(room.engines) {}
    }

    @Test("Without a room, a foreign mark stays binding — no session, no render-free")
    func roomlessKeepsOldBehaviour() {
        let vm = NotchboardViewModel()
        vm.selfMemberID = "me"
        let element = vm.activeGroup.elements.first!
        vm.workspace.members["other"] = NBMember(id: "other", name: "sam")
        vm.store.setClaim(NBClaim(who: "other"), elementID: element.id,
                          group: vm.activeGroupID, collection: vm.activeCollectionID)

        let held = vm.selectedElement(id: element.id)!
        #expect(!vm.isEffectivelyFree(held), "no presence information means the mark is taken at face value")
        vm.claimOrRelease(element.id)
        #expect(vm.selectedElement(id: element.id)?.claimedBy?.who == "other", "still refused without a takeover")
    }
}

@Suite("Room address in exports")
struct RoomTransferTests {

    @Test("The room travels — sealed broker credential included; firstSyncCompleted does not")
    func roomRoundTrips() throws {
        var room = NBRoomConfig(brokerURL: "mqtts://broker.acme.dev:8883", room: "acme-mobile")
        room.firstSyncCompleted = true // this Mac's history, not the file's business
        room.sealedBrokerPassword = Data([9, 8, 7]) // ciphertext is safe in a file

        let data = try WorkspaceTransfer.exportData(MockData.workspace(), password: "pw", room: room, rounds: 1_000)
        let file = try WorkspaceTransfer.readFile(from: data)
        #expect(file.room?.brokerURL == "mqtts://broker.acme.dev:8883")
        #expect(file.room?.room == "acme-mobile")
        #expect(file.room?.sealedBrokerPassword == Data([9, 8, 7]),
                "an importer must be able to join with just the room password")
        #expect(file.room?.firstSyncCompleted == false, "an importer has never merged — they must adopt, not double-push")
    }

    @Test("A local collection exports with no room")
    func localExportsRoomless() throws {
        let data = try WorkspaceTransfer.exportData(MockData.emptyWorkspace(), password: "pw", rounds: 1_000)
        #expect(try WorkspaceTransfer.readFile(from: data).room == nil)
    }
}

@Suite("Room key store", .serialized)
struct RoomKeyStoreTests {

    @Test("The room password round-trips, overwrites, and deletes")
    func roundTrip() {
        // A unique room per run so a crashed earlier run can't leak state in.
        let config = NBRoomConfig(brokerURL: "mqtts://user@test.invalid:8883", room: "kc-\(UUID().uuidString.prefix(8))")
        defer { RoomKeyStore.deletePasswords(for: config) }

        #expect(RoomKeyStore.roomPassword(for: config) == nil)
        #expect(RoomKeyStore.saveRoomPassword("swordfish", for: config))
        #expect(RoomKeyStore.roomPassword(for: config) == "swordfish")

        // Overwrite, not duplicate — rotation is the only revocation there is.
        #expect(RoomKeyStore.saveRoomPassword("rotated", for: config))
        #expect(RoomKeyStore.roomPassword(for: config) == "rotated")

        RoomKeyStore.deletePasswords(for: config)
        #expect(RoomKeyStore.roomPassword(for: config) == nil)
    }

    @Test("An unparseable broker URL stores nothing rather than keying on garbage")
    func unparseableRefused() {
        let config = NBRoomConfig(brokerURL: "not a url at all ://", room: "x")
        #expect(!RoomKeyStore.saveRoomPassword("pw", for: config))
        #expect(RoomKeyStore.roomPassword(for: config) == nil)
    }
}

@Suite("Room dialog accessory layout")
struct RoomAccessoryLayoutTests {

    @Test("The room-setup form keeps every field wide enough to read")
    func roomSetupSurvivesLayout() {
        let broker = PromptAccessory.makeField(NSTextField(), placeholder: "broker")
        let room = PromptAccessory.makeField(NSTextField(), placeholder: "room")
        let accountUser = PromptAccessory.makeField(NSTextField(), placeholder: "user")
        let accountPassword = PromptAccessory.makeField(NSSecureTextField(), placeholder: "pass")
        let password = PromptAccessory.makeField(NSTextField(), placeholder: "password")
        let generate = NSButton(title: "Generate", target: nil, action: nil)

        let container = PromptAccessory.roomSetup(
            broker: broker, room: room,
            accountUser: accountUser, accountPassword: accountPassword,
            password: password, generate: generate
        )
        container.layoutSubtreeIfNeeded() // the force that exposed the NSStackView collapse

        for (field, minimum) in [(broker, 300.0), (room, 300.0), (accountUser, 120.0), (accountPassword, 120.0), (password, 200.0)] {
            #expect(field.frame.width >= minimum, "a field a passphrase can't fit in is the export-password bug again")
        }
        #expect(generate.frame.width >= 80)
        #expect(!password.frame.intersects(generate.frame), "the password field must not sit under the button")
        #expect(!accountUser.frame.intersects(accountPassword.frame), "the account pair must sit side by side, not stacked")
    }

    @Test("The invite-join accessory keeps both fields wide and apart")
    func inviteJoinSurvivesLayout() {
        let invite = PromptAccessory.makeField(NSTextField(), placeholder: "i")
        let password = PromptAccessory.makeField(NSSecureTextField(), placeholder: "p")
        let container = PromptAccessory.inviteJoin(invite: invite, password: password)
        container.layoutSubtreeIfNeeded()
        #expect(!invite.frame.intersects(password.frame))
        #expect(invite.frame.width >= 300 && password.frame.width >= 300,
                "an invite line a paste can't fit in is the export-password bug again")
    }
}
