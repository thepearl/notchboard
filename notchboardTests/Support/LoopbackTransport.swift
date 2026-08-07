//
//  LoopbackTransport.swift
//  notchboardTests
//
//  An in-memory broker faithful to the transport semantics the engine relies on
//  (SyncTransport's header): retained messages replayed to new subscribers, empty payload
//  clears, last-will fired on ungraceful drops, noLocal everywhere except the publisher's
//  own sync-barrier topic. Delivery is queued and only happens inside `pump()`, so every
//  convergence test is deterministic — no async waits, no timing, no flakes.
//
//  `partition`/`heal` model a Mac dropping off the network: partition detaches the client
//  and fires its will (the broker noticing the dead TCP session); heal reattaches it and
//  reports .connected, which makes the session re-run its replay — exactly the reconnect
//  path the real MQTT transport will drive.
//

import Foundation
@testable import notchboard

@MainActor
final class LoopbackBroker {
    private(set) var retained: [String: SyncMessage] = [:]
    /// Every publish ever made — the echo-loop tests bound this.
    private(set) var publishCount = 0

    private var clients: [LoopbackTransport] = []
    private var queue: [(recipient: LoopbackTransport, message: SyncMessage)] = []
    /// Every transport ever created, in creation order — tests use this to partition a
    /// specific peer without threading the reference through the engine's factory.
    private(set) var transports: [LoopbackTransport] = []

    var lastTransport: LoopbackTransport? { transports.last }

    func makeTransport() -> LoopbackTransport {
        let transport = LoopbackTransport(broker: self)
        transports.append(transport)
        return transport
    }

    /// Delivers everything queued, including messages enqueued by the deliveries
    /// themselves, until the room is quiet.
    func pump() {
        while !queue.isEmpty {
            let (recipient, message) = queue.removeFirst()
            guard clients.contains(where: { $0 === recipient }) else { continue }
            recipient.onMessage?(message)
        }
    }

    /// The ungraceful drop: the broker notices the dead session, fires the will, and the
    /// client's own transport reports the disconnect. Subscriptions die with the session
    /// (MQTT clean start) — that is what makes the reconnect replay retained state again.
    func partition(_ transport: LoopbackTransport) {
        guard clients.contains(where: { $0 === transport }) else { return }
        clients.removeAll { $0 === transport }
        transport.subscriptions = []
        if let will = transport.lastWill {
            deliver(will, from: nil)
        }
        transport.onStateChange?(.disconnected)
    }

    func heal(_ transport: LoopbackTransport) {
        attach(transport)
        transport.onStateChange?(.connected)
    }

    // MARK: - Transport plumbing

    fileprivate func attach(_ transport: LoopbackTransport) {
        guard !clients.contains(where: { $0 === transport }) else { return }
        clients.append(transport)
    }

    fileprivate func detach(_ transport: LoopbackTransport) {
        clients.removeAll { $0 === transport }
    }

    fileprivate func publish(_ message: SyncMessage, from sender: LoopbackTransport?) {
        publishCount += 1
        if message.retained {
            if message.payload.isEmpty {
                retained.removeValue(forKey: message.topic)
            } else {
                retained[message.topic] = message
            }
        }
        deliver(message, from: sender)
    }

    /// Retained replay for a fresh subscription, delivered in sorted-topic order — which
    /// happens to put claim topics BEFORE element topics ("claim" < "el"), making the
    /// engine's ordered-apply pass load-bearing rather than decorative.
    fileprivate func replayRetained(matching filter: String, to transport: LoopbackTransport) {
        for topic in retained.keys.sorted() where Self.matches(filter: filter, topic: topic) {
            queue.append((transport, retained[topic]!))
        }
    }

    private func deliver(_ message: SyncMessage, from sender: LoopbackTransport?) {
        for client in clients {
            guard client.subscriptions.contains(where: { Self.matches(filter: $0, topic: message.topic) }) else { continue }
            // noLocal, except the sender's own barrier — the transport contract.
            if client === sender, !message.topic.contains("/sync/") { continue }
            queue.append((client, message))
        }
    }

    private static func matches(filter: String, topic: String) -> Bool {
        if filter.hasSuffix("/#") {
            return topic.hasPrefix(String(filter.dropLast(1)))
        }
        return filter == topic
    }
}

@MainActor
final class LoopbackTransport: SyncTransport {
    var onMessage: ((SyncMessage) -> Void)?
    var onStateChange: ((SyncConnectionState) -> Void)?
    var lastWill: SyncMessage?

    fileprivate var subscriptions: Set<String> = []
    private unowned let broker: LoopbackBroker

    fileprivate init(broker: LoopbackBroker) {
        self.broker = broker
    }

    func connect() {
        broker.attach(self)
        onStateChange?(.connected)
    }

    func disconnect(publishingLastWill: Bool) {
        if publishingLastWill, let will = lastWill {
            broker.publish(will, from: self)
        }
        broker.detach(self)
        // Clean start: subscriptions don't survive the session, so a reconnect
        // re-subscribes and gets a full retained replay.
        subscriptions = []
        onStateChange?(.disconnected)
    }

    func publish(_ message: SyncMessage) {
        broker.publish(message, from: self)
    }

    func subscribe(to topicFilter: String) {
        guard !subscriptions.contains(topicFilter) else { return }
        subscriptions.insert(topicFilter)
        broker.replayRetained(matching: topicFilter, to: self)
    }
}
