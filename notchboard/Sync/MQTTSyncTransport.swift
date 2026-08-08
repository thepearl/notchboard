//
//  MQTTSyncTransport.swift
//  notchboard
//
//  The production SyncTransport: MQTTNIO under a MainActor facade. Everything the engine
//  sees happens on the main actor; every NIO callback hops before touching state.
//
//  Address forms (vision.md §14.2):
//    mqtts://[user@]host[:8883]        TLS over TCP — the normal case
//    wss://[user@]host[:443][/path]    MQTT over WebSocket+TLS — the corp-firewall fallback
//    mqtt://localhost[:1883]           plaintext, LOOPBACK ONLY — the mosquitto test suite
//  Anything else refuses loudly at connect. TLS is mandatory off-machine; there is no
//  flag to weaken that, deliberately.
//
//  Semantics the engine's contract needs from MQTT:
//  - MQTT 5, clean start: subscriptions die with the session, so every reconnect re-runs
//    the retained replay — which IS the offline catch-up.
//  - QoS 1 both directions; publishes drain through an ordered outbox so a schema always
//    hits the wire before the elements that need it.
//  - noLocal on the room subscription, plus a second non-noLocal subscription to the sync
//    namespace so our own replay barrier comes back (the one echo the engine relies on).
//  - The will is the sealed offline presence; keepalive 45s bounds how long a slammed lid
//    keeps its claims rendered in-use (§14.3's "a minute or two").
//  - Reconnect is the transport's job: exponential backoff 1s → 60s while the engine
//    keeps working locally.
//

import Foundation
import MQTTNIO
import NIOCore
import NIOFoundationCompat
import NIOTransportServices
import os

@MainActor
final class MQTTSyncTransport: SyncTransport {
    var onMessage: ((SyncMessage) -> Void)?
    var onStateChange: ((SyncConnectionState) -> Void)?
    var lastWill: SyncMessage?

    private struct Endpoint {
        var host: String
        var port: Int
        var username: String?
        var useSSL: Bool
        var useWebSocket: Bool
        var webSocketPath: String
    }

    private let endpoint: Endpoint?
    private let addressProblem: String?
    /// Stable per-member client id ("nb-<memberID>"): a second connect from the same Mac
    /// supersedes the old broker session instead of ghosting beside it.
    private let clientIdentifier: String
    /// The broker account's password (persona 2's shared credential — HiveMQ Cloud and
    /// friends). NOT the room password, which never reaches the transport at all; it only
    /// ever derives the payload key. The matching username rides in the broker URL.
    private let brokerPassword: String?

    private var client: MQTTClient?
    private var wantsConnection = false
    private var reconnectDelay: TimeInterval = 1
    private var reconnectTask: Task<Void, Never>?
    private var outbox: [SyncMessage] = []
    private var draining = false
    /// Publishes wait for in-flight SUBACKs. Without this, a publish can beat the
    /// subscription to the broker, and the broker then hands our own message back as
    /// retained replay — noLocal only suppresses *live* forwarding, not replay. It also
    /// guarantees the engine's replay barrier is published into a live subscription.
    private var pendingSubscribes = 0

    private static let logger = Logger(subsystem: "flourix.notchboard", category: "sync")
    private static let keepAlive: Int64 = 45
    private static let maxReconnectDelay: TimeInterval = 60

    init(config: NBRoomConfig, memberID: String, brokerPassword: String? = nil) {
        self.clientIdentifier = "nb-\(memberID)"
        self.brokerPassword = brokerPassword
        switch Self.parse(config.brokerURL) {
        case .usable(let endpoint):
            self.endpoint = endpoint
            self.addressProblem = nil
        case .refused(let problem):
            self.endpoint = nil
            self.addressProblem = problem
        }
    }

    deinit {
        // MQTTNIO traps if a client deallocates without shutdown. Normal teardown goes
        // through disconnect(); this is the safety net for a dropped session.
        try? client?.syncShutdownGracefully()
    }

    // MARK: SyncTransport

    func connect() {
        guard let endpoint else {
            onStateChange?(.failed(addressProblem ?? "unusable broker address"))
            return
        }
        wantsConnection = true
        reconnectTask?.cancel()
        attemptConnect(endpoint)
    }

    func disconnect(publishingLastWill: Bool) {
        // The graceful path: MQTT's normal DISCONNECT suppresses the will by protocol,
        // and the engine has already published its own offline presence. (The
        // `publishingLastWill: true` variant only exists for the loopback fake — an
        // ungraceful drop here IS the will firing, no code needed.)
        wantsConnection = false
        reconnectTask?.cancel()
        // Flush before closing: the goodbye sequence is publish-offline-presence THEN
        // disconnect, and dropping the queue here would eat exactly that message — the
        // peer would wait out the keepalive instead of seeing the claims free now.
        let remaining = outbox
        outbox = []
        guard let client else { return }
        self.client = nil
        Task {
            for message in remaining where client.isActive() {
                var properties = MQTTProperties()
                if let expiry = message.expirySeconds {
                    properties.append(.messageExpiry(expiry))
                }
                _ = try? await client.v5.publish(
                    to: message.topic,
                    payload: ByteBuffer(data: message.payload),
                    qos: .atLeastOnce,
                    retain: message.retained,
                    properties: properties
                )
            }
            try? await client.v5.disconnect()
            try? await client.shutdown()
        }
    }

    func publish(_ message: SyncMessage) {
        outbox.append(message)
        drainOutbox()
    }

    func subscribe(to topicFilter: String) {
        guard let client else { return }
        var infos = [MQTTSubscribeInfoV5(topicFilter: topicFilter, qos: .atLeastOnce, noLocal: true)]
        if topicFilter.hasSuffix("/#") {
            // The barrier-echo exception (see SyncTransport's header): the sync namespace
            // subscribes WITHOUT noLocal so our own replay barrier comes back to us.
            let syncFilter = String(topicFilter.dropLast(1)) + "sync/#"
            infos.append(MQTTSubscribeInfoV5(topicFilter: syncFilter, qos: .atLeastOnce, noLocal: false))
        }
        pendingSubscribes += 1
        Task { [weak self] in
            do {
                _ = try await client.v5.subscribe(to: infos)
                await MainActor.run { [weak self] in
                    self?.pendingSubscribes -= 1
                    self?.drainOutbox()
                }
            } catch {
                Self.logger.error("subscribe failed: \(error)")
                // This Task inherits the transport's main-actor isolation, so both calls
                // are plain synchronous calls here.
                self?.pendingSubscribes -= 1
                self?.handleConnectionLoss()
            }
        }
    }

    // MARK: Connection lifecycle

    private func attemptConnect(_ endpoint: Endpoint) {
        onStateChange?(.connecting)

        let configuration = MQTTClient.Configuration(
            version: .v5_0,
            keepAliveInterval: .seconds(Self.keepAlive),
            userName: endpoint.username,
            password: brokerPassword,
            useSSL: endpoint.useSSL,
            useWebSockets: endpoint.useWebSocket,
            webSocketURLPath: endpoint.webSocketPath
        )
        // A fresh client per attempt: MQTTNIO clients are cheap, and reusing one across
        // failed handshakes accumulates listeners and half-closed state. The event-loop
        // group is the shared NIOTS singleton — per-client groups were deprecated, and
        // Network.framework's group is what gives TLS via Transport Services on macOS.
        let client = MQTTClient(
            host: endpoint.host,
            port: endpoint.port,
            identifier: clientIdentifier,
            eventLoopGroupProvider: .shared(NIOTSEventLoopGroup.singleton),
            configuration: configuration
        )
        self.client = client

        client.addPublishListener(named: "notchboard") { [weak self] result in
            guard case .success(let info) = result else { return }
            let message = SyncMessage(
                topic: info.topicName,
                payload: Data(buffer: info.payload),
                retained: info.retain
            )
            Task { @MainActor [weak self] in
                self?.onMessage?(message)
            }
        }
        client.addCloseListener(named: "notchboard") { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleConnectionLoss()
            }
        }

        let will: (topicName: String, payload: ByteBuffer, qos: MQTTQoS, retain: Bool, properties: MQTTProperties)? =
            lastWill.map { ($0.topic, ByteBuffer(data: $0.payload), .atLeastOnce, true, .init()) }

        Task { [weak self] in
            do {
                _ = try await client.v5.connect(cleanStart: true, will: will)
                await MainActor.run { [weak self] in
                    guard let self, self.wantsConnection, self.client === client else { return }
                    self.reconnectDelay = 1
                    self.onStateChange?(.connected)
                    self.drainOutbox()
                }
            } catch {
                Self.logger.error("connect to \(endpoint.host, privacy: .public):\(endpoint.port) failed: \(error)")
                try? await client.shutdown()
                await MainActor.run { [weak self] in
                    guard let self, self.wantsConnection else { return }
                    if self.client === client { self.client = nil }
                    self.onStateChange?(.failed("room unreachable — retrying"))
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func handleConnectionLoss() {
        guard wantsConnection else { return }
        if let dead = client {
            client = nil
            Task { try? await dead.shutdown() }
        }
        onStateChange?(.disconnected)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard wantsConnection, let endpoint else { return }
        reconnectTask?.cancel()
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, Self.maxReconnectDelay)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            guard let self, self.wantsConnection, self.client == nil else { return }
            self.attemptConnect(endpoint)
        }
    }

    /// Serialised sends: one drain loop awaits each publish in turn, so cross-topic
    /// ordering survives (a schema always lands before its elements). A send that fails
    /// is dropped — reconcile-push on the next connect is the catch-up, not a local queue.
    private func drainOutbox() {
        guard !draining, pendingSubscribes == 0, let client, client.isActive() else { return }
        draining = true
        Task { [weak self] in
            while let self, let client = self.client, self.pendingSubscribes == 0, !self.outbox.isEmpty {
                let message = self.outbox.removeFirst()
                var properties = MQTTProperties()
                if let expiry = message.expirySeconds {
                    properties.append(.messageExpiry(expiry))
                }
                do {
                    _ = try await client.v5.publish(
                        to: message.topic,
                        payload: ByteBuffer(data: message.payload),
                        qos: .atLeastOnce,
                        retain: message.retained,
                        properties: properties
                    )
                } catch {
                    Self.logger.error("publish to \(message.topic, privacy: .public) failed: \(error)")
                }
            }
            self?.draining = false
        }
    }

    // MARK: Address parsing

    private enum ParsedAddress {
        case usable(Endpoint)
        case refused(String)
    }

    private static func parse(_ brokerURL: String) -> ParsedAddress {
        guard let url = URL(string: brokerURL), let host = url.host(), !host.isEmpty else {
            return .refused("“\(brokerURL)” isn't a usable broker address")
        }
        let username = url.user(percentEncoded: false)
        switch url.scheme {
        case "mqtts":
            return .usable(Endpoint(host: host, port: url.port ?? 8883, username: username,
                                    useSSL: true, useWebSocket: false, webSocketPath: "/mqtt"))
        case "wss":
            return .usable(Endpoint(host: host, port: url.port ?? 443, username: username,
                                    useSSL: true, useWebSocket: true,
                                    webSocketPath: url.path.isEmpty ? "/mqtt" : url.path))
        case "mqtt":
            // Plaintext is loopback-only: the integration suite's local mosquitto.
            // Credentials over cleartext to a real host is exactly the mistake this
            // refuses to allow (§14.2: TLS mandatory).
            guard ["localhost", "127.0.0.1", "::1"].contains(host) else {
                return .refused("mqtt:// is allowed for localhost only — use mqtts:// for \(host)")
            }
            return .usable(Endpoint(host: host, port: url.port ?? 1883, username: username,
                                    useSSL: false, useWebSocket: false, webSocketPath: "/mqtt"))
        default:
            return .refused("use mqtts://host, wss://host, or mqtt://localhost — not \(url.scheme ?? "a bare address")")
        }
    }
}
