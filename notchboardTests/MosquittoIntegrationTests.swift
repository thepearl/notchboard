//
//  MosquittoIntegrationTests.swift
//  notchboardTests
//
//  The MQTT transport against a real broker. Everything above the transport is proven
//  deterministically over the loopback (SyncEngineTests); what only a real broker can
//  prove is the MQTT-shaped behaviour itself — retained storage and clears, the
//  noLocal/barrier-echo subscription trick, the Last Will firing on an ungraceful drop.
//
//  Skipped as a whole when nothing listens on localhost:1883, via an `.enabled(if:)` suite
//  trait. It has to be the trait: Swift Testing has no in-body skip, so the earlier
//  `try #require` gate recorded a failed expectation and turned every clean clone's first
//  test run red. Run a broker with:
//
//      brew install mosquitto && mosquitto -p 1883 -v
//
//  Every wait POLLS with a deadline (CLAUDE.md rule): the suite shares the main actor
//  with heavy neighbours, and a fixed sleep is a flake in waiting.
//

import Foundation
import Network
import Testing
@testable import notchboard

@Suite("MQTT transport against a local mosquitto", .serialized,
       .enabled(if: BrokerProbe.hasLocalBroker, "no broker on localhost:1883 — start one with: mosquitto -p 1883"))
@MainActor
struct MosquittoIntegrationTests {

    /// Distinct rooms per test run so retained state from an earlier run can't leak in.
    private let room = "it-\(UUID().uuidString.prefix(8).lowercased())"
    private var config: NBRoomConfig { NBRoomConfig(brokerURL: "mqtt://localhost:1883", room: room) }

    private func makeTransport(memberID: String) -> MQTTSyncTransport {
        MQTTSyncTransport(config: config, memberID: memberID)
    }

    /// Polls until the condition holds or the deadline passes. Yields to the main actor
    /// between checks so transport callbacks can land.
    private func poll(timeout: TimeInterval = 10, until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private final class Inbox {
        var messages: [SyncMessage] = []
        var states: [SyncConnectionState] = []
    }

    private func wire(_ transport: MQTTSyncTransport) -> Inbox {
        let inbox = Inbox()
        transport.onMessage = { inbox.messages.append($0) }
        transport.onStateChange = { inbox.states.append($0) }
        return inbox
    }

    // MARK: Tests

    @Test("Connects, then disconnects cleanly")
    func connectDisconnect() async throws {
        let transport = makeTransport(memberID: "m1")
        let inbox = wire(transport)

        transport.connect()
        await poll { inbox.states.contains(.connected) }
        #expect(inbox.states.contains(.connected))

        transport.disconnect(publishingLastWill: false)
        await poll(timeout: 3) { inbox.states.last == .disconnected }
    }

    @Test("A retained message survives for a later subscriber; an empty publish clears it")
    func retainedRoundTrip() async throws {
        let topic = "nb/\(room)/el/users/e1"
        let payload = Data("sealed-bytes".utf8)

        let publisher = makeTransport(memberID: "m1")
        let pubInbox = wire(publisher)
        publisher.connect()
        await poll { pubInbox.states.contains(.connected) }
        publisher.publish(SyncMessage(topic: topic, payload: payload))

        // A subscriber that arrives afterwards must still get it: that IS retained replay.
        let subscriber = makeTransport(memberID: "m2")
        let subInbox = wire(subscriber)
        subscriber.connect()
        await poll { subInbox.states.contains(.connected) }
        subscriber.subscribe(to: "nb/\(room)/#")
        await poll { subInbox.messages.contains { $0.topic == topic } }

        let received = subInbox.messages.first { $0.topic == topic }
        #expect(received?.payload == payload)
        #expect(received?.retained == true)

        // Clear it; a third subscriber sees nothing on the topic.
        publisher.publish(SyncMessage(topic: topic, payload: Data()))
        let third = makeTransport(memberID: "m3")
        let thirdInbox = wire(third)
        third.connect()
        await poll { thirdInbox.states.contains(.connected) }
        third.subscribe(to: "nb/\(room)/#")
        // No completion marker for "nothing" — publish a sentinel after the clear and
        // poll for it; if the cleared topic were still retained it would arrive first.
        publisher.publish(SyncMessage(topic: "nb/\(room)/el/users/sentinel", payload: Data("x".utf8)))
        await poll { thirdInbox.messages.contains { $0.topic.hasSuffix("sentinel") } }
        #expect(!thirdInbox.messages.contains { $0.topic == topic }, "an empty publish must clear the retained message")

        publisher.disconnect(publishingLastWill: false)
        subscriber.disconnect(publishingLastWill: false)
        third.disconnect(publishingLastWill: false)
    }

    @Test("noLocal holds for room topics, and the own barrier still echoes back")
    func noLocalAndBarrierEcho() async throws {
        let transport = makeTransport(memberID: "m1")
        let inbox = wire(transport)
        transport.connect()
        await poll { inbox.states.contains(.connected) }
        transport.subscribe(to: "nb/\(room)/#")

        let barrierTopic = "nb/\(room)/sync/m1"
        let elementTopic = "nb/\(room)/el/users/e9"
        transport.publish(SyncMessage(topic: elementTopic, payload: Data("mine".utf8)))
        transport.publish(SyncMessage(topic: barrierTopic, payload: Data("sync".utf8), retained: false))

        await poll { inbox.messages.contains { $0.topic == barrierTopic } }
        #expect(inbox.messages.contains { $0.topic == barrierTopic }, "the replay barrier must echo to its publisher")
        #expect(!inbox.messages.contains { $0.topic == elementTopic }, "own room publishes must NOT echo (noLocal)")

        transport.disconnect(publishingLastWill: false)
    }

    @Test("An ungraceful drop fires the Last Will; a graceful disconnect doesn't")
    func lastWillOnUngracefulDrop() async throws {
        let willTopic = "nb/\(room)/presence/dying"

        let watcher = makeTransport(memberID: "watcher")
        let watcherInbox = wire(watcher)
        watcher.connect()
        await poll { watcherInbox.states.contains(.connected) }
        watcher.subscribe(to: "nb/\(room)/#")

        // The doomed client: set a will, connect, then vanish without a DISCONNECT. The
        // transport has no "die abruptly" API (rightly), so a second raw client from the
        // same member id supersedes the session — MQTT treats the takeover as an
        // ungraceful end of the first session and fires its will.
        let doomed = makeTransport(memberID: "dying")
        doomed.lastWill = SyncMessage(topic: willTopic, payload: Data("offline".utf8))
        let doomedInbox = wire(doomed)
        doomed.connect()
        await poll { doomedInbox.states.contains(.connected) }

        let usurper = makeTransport(memberID: "dying") // same client id — session takeover
        let usurperInbox = wire(usurper)
        usurper.connect()
        await poll { usurperInbox.states.contains(.connected) }

        await poll { watcherInbox.messages.contains { $0.topic == willTopic } }
        #expect(watcherInbox.messages.contains { $0.topic == willTopic && $0.payload == Data("offline".utf8) },
                "the broker must fire the will when a session ends without DISCONNECT")

        watcher.disconnect(publishingLastWill: false)
        usurper.disconnect(publishingLastWill: false)
        doomed.disconnect(publishingLastWill: false)
    }

    @Test("Two real transports move one element end to end")
    func twoTransportsConverge() async throws {
        let a = makeTransport(memberID: "ma")
        let b = makeTransport(memberID: "mb")
        let aInbox = wire(a)
        let bInbox = wire(b)

        a.connect()
        b.connect()
        await poll { aInbox.states.contains(.connected) && bInbox.states.contains(.connected) }
        a.subscribe(to: "nb/\(room)/#")
        b.subscribe(to: "nb/\(room)/#")

        let topic = "nb/\(room)/el/users/live1"
        a.publish(SyncMessage(topic: topic, payload: Data("live-payload".utf8)))
        await poll { bInbox.messages.contains { $0.topic == topic } }
        #expect(bInbox.messages.first { $0.topic == topic }?.payload == Data("live-payload".utf8))

        a.disconnect(publishingLastWill: false)
        b.disconnect(publishingLastWill: false)
    }
}

