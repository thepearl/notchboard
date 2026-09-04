//
//  SyncTransport.swift
//  notchboard
//
//  What the sync engine needs from a message transport — and nothing more. Two real
//  implementations: the MQTT client (production) and the loopback broker (tests). This is
//  the repo's first protocol; it earns the abstraction because the engine's convergence
//  rules are exactly the code that must be testable with no network and no timing.
//
//  Semantics the engine relies on, which any implementation must honour:
//  - A retained message is stored per topic and replayed to every new subscriber.
//  - Publishing an EMPTY payload to a retained topic clears it (correct for claims only —
//    deletions are real tombstone payloads, see SyncPayloads).
//  - `lastWill` is published by the broker if the connection dies without a graceful
//    disconnect — presence correctness for the closed-lid case.
//  - Subscribers never receive their own publishes (MQTT 5 noLocal; the loopback mirrors
//    it) — EXCEPT on the sync barrier namespace (nb/<room>/sync/…), which must echo back
//    to its publisher: hearing our own barrier after subscribing is how the engine knows
//    retained replay is complete. MQTT implements this as an overlapping subscription to
//    the own-barrier topic without the noLocal flag. The engine is idempotent against
//    other echoes anyway, but not receiving them is what keeps a busy room cheap.
//

import Foundation

struct SyncMessage: Sendable, Equatable {
    var topic: String
    /// Empty = clear the retained message on this topic.
    var payload: Data
    var retained: Bool
    /// MQTT 5 message-expiry, used to let broker-side tombstones age out in step with the
    /// local prune (NBTombstone.retention). nil = no expiry.
    var expirySeconds: UInt32?

    init(topic: String, payload: Data, retained: Bool = true, expirySeconds: UInt32? = nil) {
        self.topic = topic
        self.payload = payload
        self.retained = retained
        self.expirySeconds = expirySeconds
    }
}

enum SyncConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    /// Failures surface loudly (§14.2) — the message is user-facing via the view model.
    case failed(String)
}

@MainActor
protocol SyncTransport: AnyObject {
    /// Inbound messages — retained replay after subscribing, then live traffic.
    var onMessage: ((SyncMessage) -> Void)? { get set }
    var onStateChange: ((SyncConnectionState) -> Void)? { get set }
    /// Published by the broker if this client dies ungracefully. Set before `connect()`.
    var lastWill: SyncMessage? { get set }

    func connect()
    /// `publishingLastWill` = false is the graceful path: the caller has already published
    /// its own offline presence and the will must NOT fire on top of it.
    func disconnect(publishingLastWill: Bool)
    func publish(_ message: SyncMessage)
    func subscribe(to topicFilter: String)
    /// Waits for a graceful `disconnect` to finish flushing (the goodbye is published from a
    /// task the transport spawns), or for the deadline, whichever comes first. Only the quit
    /// path cares (AppDelegate.applicationShouldTerminate); the loopback fake has nothing to
    /// wait for, hence the default.
    func awaitDisconnect(until deadline: ContinuousClock.Instant) async
}

extension SyncTransport {
    func awaitDisconnect(until deadline: ContinuousClock.Instant) async {}
}

/// Waits for `task`, or until `deadline`, whichever lands first — and really returns at the
/// deadline. A task group cannot do this: it awaits every child before returning, and
/// `Task<Void, Never>.value` has no way to answer the cancellation the group sends, so a
/// racing group returns when the *task* finishes however long that takes (measured: a
/// one-second cap over a five-second task returned after five seconds). The quit path is the
/// caller, so an unbounded wait here is a Mac that will not shut down behind a dead broker.
func awaitCompletion(of task: Task<Void, Never>, until deadline: ContinuousClock.Instant) async {
    let gate = FirstWinsGate()
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        gate.arm(continuation)
        Task {
            await task.value
            gate.resume()
        }
        Task {
            try? await Task.sleep(until: deadline, clock: .continuous)
            gate.resume()
        }
    }
}

/// Resumes its continuation exactly once, for whichever waiter arrives first.
private final class FirstWinsGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func arm(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
