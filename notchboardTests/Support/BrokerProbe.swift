//
//  BrokerProbe.swift
//  notchboardTests
//
//  The skip gate for suites that need a real MQTT broker: a plain TCP connect to
//  localhost:1883 (no MQTT handshake, so a hung broker still skips fast). Shared by
//  MosquittoIntegrationTests and PeerHarnessTests so the probe can't drift between them,
//  and read from their `.enabled(if:)` traits — which is why it cannot be private to either.
//

import Foundation
import Network

enum BrokerProbe {
    /// True when something accepts TCP on localhost:1883. Computed once per process.
    nonisolated static let hasLocalBroker: Bool = {
        let connection = NWConnection(host: "127.0.0.1", port: 1883, using: .tcp)
        let gate = DispatchSemaphore(value: 0)
        let reachable = LockedFlag()
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                reachable.set()
                gate.signal()
            case .failed, .cancelled:
                gate.signal()
            default:
                break
            }
        }
        connection.start(queue: DispatchQueue(label: "nb.broker.probe"))
        _ = gate.wait(timeout: .now() + 1)
        connection.cancel()
        return reachable.isSet
    }()

    /// One-shot thread-safe flag — touched from the NWConnection queue, never an actor.
    private nonisolated final class LockedFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func set() {
            lock.lock()
            value = true
            lock.unlock()
        }

        var isSet: Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }
}
