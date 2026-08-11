//
//  SyncEngine.swift
//  notchboard
//
//  The room state machine (vision.md §14.2). One RoomSession per room-joined collection,
//  coordinated by SyncEngine: local changes flow store → changeSink → engine → session →
//  transport; remote messages flow transport → session → the store's emission-free
//  remote-apply path. The engine never toasts — like CollectionStore, it reports events
//  and the view model decides what to say (and owns the "in use", never "claim" copy).
//
//  Connect sequence, and the two subtleties in it:
//
//  1. Retained replay has no "done" marker, so the session publishes a NON-retained
//     barrier to its own sync topic right after subscribing: the broker delivers all
//     retained state first, then the barrier, so hearing our own barrier means replay is
//     complete (with a quiet-period fallback in case a broker drops it).
//  2. Replay is unordered across topics — a claim can arrive before its element — so the
//     buffered messages are applied in structural order: meta → schemas → elements →
//     claims → presence. Live traffic gets a small deferred-retry buffer for the same
//     reason.
//
//  First connect is asymmetric by design: an empty room is seeded from local state, a
//  non-empty room REPLACES a never-synced collection (after a forced snapshot). That
//  asymmetry is what keeps two teammates who imported the same file from double-pushing
//  every row under re-minted element ids.
//
//  Observation note: `state` and `onlineMemberIDs` are read by the header and notch, and
//  writes go through equality guards for the same reason SimulatorWindowTracker's do —
//  Observation notifies on writes, not changes, and retained presence re-publishes must
//  not re-render the panel.
//

import CryptoKit
import Foundation
import os

/// What a session wants the user to know. The view model translates these into toasts
/// and notifications; the engine never renders copy.
enum RoomEvent: Equatable {
    case connected(onlineCount: Int)
    case wrongPassword
    case failed(String)
    /// This Mac adopted the room's catalogue on first connect (its local copy was
    /// snapshotted first).
    case adoptedRoomState(elementCount: Int)
    /// An element someone may be watching was released remotely (or its holder went
    /// offline) — the notify-when-free trigger.
    case elementFreed(NBElement)
}

// MARK: - RoomSession

@Observable @MainActor
final class RoomSession {
    let collectionID: String
    private(set) var config: NBRoomConfig
    private(set) var state: SyncConnectionState = .disconnected
    /// Who is online right now, per retained presence. Excludes self.
    private(set) var onlineMemberIDs: Set<String> = []

    @ObservationIgnored private let transport: SyncTransport
    @ObservationIgnored private let store: CollectionStore
    @ObservationIgnored private let codec: SyncCodec
    @ObservationIgnored private let selfMemberID: String
    @ObservationIgnored var selfName: String
    @ObservationIgnored var onEvent: ((RoomEvent) -> Void)?

    @ObservationIgnored private var isReplaying = false
    @ObservationIgnored private var replayBuffer: [SyncMessage] = []
    @ObservationIgnored private var replayFallback: Task<Void, Never>?
    /// Live messages that arrived before their target existed (claim before element,
    /// element before schema). Retried after every structural apply, dropped after 10s.
    @ObservationIgnored private var deferred: [(message: SyncMessage, at: Date)] = []

    @ObservationIgnored private static let logger = Logger(subsystem: "flourix.notchboard", category: "sync")
    private static let replayQuietFallback: Duration = .seconds(3)
    private static let deferredLifetime: TimeInterval = 10

    init(collectionID: String, config: NBRoomConfig, transport: SyncTransport,
         store: CollectionStore, key: SymmetricKey, selfMemberID: String, selfName: String) {
        self.collectionID = collectionID
        self.config = config
        self.transport = transport
        self.store = store
        self.codec = SyncCodec(key: key)
        self.selfMemberID = selfMemberID
        self.selfName = selfName
    }

    // MARK: Lifecycle

    func connect() {
        guard state != .connecting, state != .connected else { return }
        setState(.connecting)
        transport.lastWill = presenceMessage(.offline)
        transport.onStateChange = { [weak self] transportState in
            self?.transportStateChanged(transportState)
        }
        transport.onMessage = { [weak self] message in
            self?.received(message)
        }
        transport.connect()
    }

    /// Graceful goodbye: retained offline presence, then disconnect without the will.
    func suspend() {
        replayFallback?.cancel()
        isReplaying = false
        if state == .connected {
            transport.publish(presenceMessage(.offline))
        }
        transport.disconnect(publishingLastWill: false)
        setState(.disconnected)
        setOnlineMembers([])
    }

    func resume() {
        guard state == .disconnected else { return }
        connect()
    }

    /// A claim renders free when its holder is offline — the live twin of
    /// releaseOrphanedClaims, and strictly a rendering rule: presence flicker must never
    /// mutate the catalogue.
    func isEffectivelyFree(_ claim: NBClaim) -> Bool {
        claim.who != selfMemberID && !onlineMemberIDs.contains(claim.who)
    }

    // MARK: Transport events

    private func transportStateChanged(_ transportState: SyncConnectionState) {
        switch transportState {
        case .connected:
            beginReplay()
        case .failed(let message):
            // Only on the transition into failure. The transport retries with backoff and
            // reports every attempt, so an unreachable broker — a mistyped host, a closed lid
            // on a train — used to post a red toast every 1, 2, 4, … 60 seconds for as long as
            // the app ran, one stream per room. `setState` was already guarded; the event was
            // not, which bypassed the guard right beside it.
            let wasAlreadyFailed = state == .failed(message)
            setState(.failed(message))
            if !wasAlreadyFailed { onEvent?(.failed(message)) }
        case .disconnected:
            // A drop mid-session: surface it, keep working locally. The transport owns
            // reconnecting; a successful reconnect restarts replay via .connected.
            if state == .connected || state == .connecting {
                setState(.disconnected)
                setOnlineMembers([])
            }
        case .connecting:
            setState(.connecting)
        }
    }

    private func beginReplay() {
        isReplaying = true
        replayBuffer = []
        transport.subscribe(to: SyncTopic.allTopics(room: config.room))
        // Non-retained: the broker delivers all retained state to a fresh subscriber
        // first, so our own barrier coming back marks the end of replay.
        transport.publish(SyncMessage(
            topic: SyncTopic.syncBarrier(memberID: selfMemberID).string(room: config.room),
            payload: Data("sync".utf8),
            retained: false
        ))
        replayFallback?.cancel()
        replayFallback = Task { [weak self] in
            try? await Task.sleep(for: Self.replayQuietFallback)
            guard !Task.isCancelled else { return }
            Self.logger.warning("replay barrier never returned — finishing replay on the quiet-period fallback")
            self?.finishReplay(barrierReturned: false)
        }
    }

    private func received(_ message: SyncMessage) {
        guard let topic = SyncTopic.parse(message.topic, room: config.room) else { return }
        if isReplaying {
            if case .syncBarrier(let memberID) = topic, memberID == selfMemberID {
                finishReplay(barrierReturned: true)
            } else if case .syncBarrier = topic {
                // someone else joining — not our replay's business
            } else {
                replayBuffer.append(message)
            }
            return
        }
        handleLive(topic: topic, message: message)
    }

    // MARK: Replay

    /// `barrierReturned` distinguishes a complete replay (our own barrier came back, so the
    /// broker has handed over everything it holds) from the quiet-period fallback, which may
    /// have seen only part of the room. Anything that treats the room as authoritative must
    /// only act on the former.
    private func finishReplay(barrierReturned: Bool) {
        guard isReplaying else { return }
        isReplaying = false
        replayFallback?.cancel()

        let buffer = replayBuffer
        replayBuffer = []

        // The adopt-vs-merge decision needs only topic kinds, not payloads: any schema or
        // element topic means the room holds a catalogue.
        let roomIsEmpty = !buffer.contains { message in
            switch SyncTopic.parse(message.topic, room: config.room) {
            case .schema, .element: return true
            default: return false
            }
        }

        // Prove the password BEFORE any destructive step: emptying the local catalogue on the
        // strength of ciphertext we can't even read would turn a typo into data loss.
        //
        // "Can ANY sealed payload be opened", not "does an arbitrary first one open". The topic
        // grammar namespaces a room by its slug alone, so a single foreign retained message —
        // another team that picked the same slug, or anything at all published to an open
        // broker's `nb/#` — used to read exactly like a wrong password and fail the whole join.
        // A wrong password cannot open ANY of them, which is the signal worth failing closed on.
        let key = codec.key
        let sealedPayloads = buffer.map(\.payload).filter { !$0.isEmpty }
        let openableCount = sealedPayloads.filter { (try? RoomCrypto.open($0, key: key)) != nil }.count
        let sealedCount = sealedPayloads.count
        if sealedCount > 0, openableCount == 0 {
            Self.logger.error("no replay payload authenticated — wrong room password")
            setState(.failed("wrong room password"))
            transport.disconnect(publishingLastWill: false)
            onEvent?(.wrongPassword)
            return
        }
        if openableCount < sealedCount {
            Self.logger.error("skipping \(sealedCount - openableCount, privacy: .public) retained payload(s) this room key cannot open")
        }

        if !roomIsEmpty, !config.firstSyncCompleted {
            // Never merged with this room: adopt its state wholesale. Snapshot first so
            // a mis-join is reversible, then empty the local copy — this is what keeps
            // two imports of the same file from double-pushing re-minted element ids.
            SnapshotStore.recordIfDue(collections: store.collections, activeCollectionID: store.activeCollectionID, force: true)
            store.resetForRoomAdoption(collectionID: collectionID)
        }

        let summary = apply(buffer)

        if roomIsEmpty {
            seedRoom()
        } else if config.firstSyncCompleted {
            reconcilePush(against: summary)
        } else {
            onEvent?(.adoptedRoomState(elementCount: currentWorkspace?.elementCount ?? 0))
        }

        if !config.firstSyncCompleted {
            config.firstSyncCompleted = true
            store.setRoomConfig(config, collectionID: collectionID)
        }

        // Only on a complete replay: a truncated one looks like "nobody holds anything" and
        // would wrongly free every row in the collection.
        if barrierReturned { clearForeignClaimsAbsentFromRoom(summary) }

        transport.publish(presenceMessage(.online))
        setState(.connected)
        onEvent?(.connected(onlineCount: onlineMemberIDs.count))
    }

    /// Drops any mark held by someone else that the room no longer carries.
    ///
    /// Releasing publishes an EMPTY payload, which deletes the retained topic rather than
    /// sending a "released" message. So a teammate who released while this Mac was asleep left
    /// nothing behind to arrive on reconnect: the row stayed "in use by them" forever, and
    /// `claimOrRelease` refuses to release a mark you don't own, so the user could not clear it
    /// either. After a complete replay the room's retained claims are authoritative for other
    /// people's marks, and absence means free.
    ///
    /// Own marks are deliberately untouched: reconcilePush re-publishes those.
    private func clearForeignClaimsAbsentFromRoom(_ summary: ReplaySummary) {
        guard let workspace = currentWorkspace else { return }
        for group in workspace.groups.values {
            for element in group.elements {
                guard let claim = element.claimedBy,
                      claim.who != selfMemberID,
                      summary.claims[element.id] == nil else { continue }
                // The emission-free remote-apply path: this is the room telling us, not a
                // local edit, so it must not travel back out (CLAUDE.md sync invariant 1).
                _ = store.applyRemoteClaim(nil, claimantName: "", elementID: element.id,
                                           collectionID: collectionID, selfID: selfMemberID)
            }
        }
    }

    private struct ReplaySummary {
        /// Newest known stamp per element on the broker — content updatedAt or tombstone
        /// deletedAt, whichever the topic held.
        var elementStamps: [String: Date] = [:]
        var schemaStamps: [String: Date] = [:]
        var tombstonedElementIDs: Set<String> = []
        var tombstonedGroupIDs: Set<String> = []
        /// elementID → claimant memberID, per the broker's retained claims.
        var claims: [String: String] = [:]
    }

    /// Applies buffered replay in structural order. Returns what the broker knew, for
    /// reconcile-push.
    private func apply(_ buffer: [SyncMessage]) -> ReplaySummary {
        var summary = ReplaySummary()

        func rank(_ topic: SyncTopic) -> Int {
            switch topic {
            case .meta: return 0
            case .schema: return 1
            case .element: return 2
            case .claim: return 3
            case .presence: return 4
            case .syncBarrier: return 5
            }
        }

        let ordered = buffer
            .compactMap { message -> (SyncTopic, SyncMessage)? in
                SyncTopic.parse(message.topic, room: config.room).map { ($0, message) }
            }
            .sorted { rank($0.0) < rank($1.0) }

        for (topic, message) in ordered {
            do {
                _ = try applyOne(topic: topic, message: message, summary: &summary)
            } catch TransferCrypto.CryptoError.wrongPassword {
                // Skip, exactly as the live path does. Aborting here was worse than useless:
                // finishReplay has already proved the key opens this room, so a payload that
                // fails now is a foreign message on a shared topic tree, and returning early
                // left the catalogue half-applied on top of an adopt-time reset.
                Self.logger.error("replay payload failed authentication on \(message.topic, privacy: .public) — ignored")
            } catch {
                Self.logger.error("unreadable replay payload on \(message.topic, privacy: .public): \(error)")
            }
        }
        return summary
    }

    // MARK: Live traffic

    private func handleLive(topic: SyncTopic, message: SyncMessage) {
        var throwaway = ReplaySummary()
        do {
            if try applyOne(topic: topic, message: message, summary: &throwaway) {
                deferred.append((message, Date()))
            }
        } catch TransferCrypto.CryptoError.wrongPassword {
            // Replay already proved the password; a single unauthenticated live message
            // is a poison payload, not a reason to kill the session.
            Self.logger.error("live payload failed authentication on \(message.topic, privacy: .public) — ignored")
        } catch {
            Self.logger.error("unreadable live payload on \(message.topic, privacy: .public): \(error)")
        }
        retryDeferred()
    }

    /// One message, one apply. Shared by replay and live paths; `summary` records what
    /// the broker held for reconcile-push. Returns true when the target doesn't exist
    /// yet (`.deferred`) so the caller can decide whether and how to buffer it.
    @discardableResult
    private func applyOne(topic: SyncTopic, message: SyncMessage, summary: inout ReplaySummary) throws -> Bool {
        switch topic {
        case .meta:
            let meta = try codec.open(SyncMetaPayload.self, from: message.payload)
            _ = store.applyRemoteMeta(name: meta.name, updatedAt: meta.updatedAt, collectionID: collectionID)

        case .schema(let groupID):
            switch try codec.openTopicMessage(SyncSchemaPayload.self, from: message.payload) {
            case .content(let payload):
                summary.schemaStamps[groupID] = payload.updatedAt
                _ = store.applyRemoteSchema(payload.toGroup(), sortIndex: payload.sortIndex, collectionID: collectionID)
            case .tombstone(let stone):
                summary.tombstonedGroupIDs.insert(groupID)
                summary.schemaStamps[groupID] = stone.deletedAt
                _ = store.applyRemoteGroupTombstone(groupID: groupID, collectionID: collectionID,
                                                    deletedAt: stone.deletedAt, by: stone.by)
            }

        case .element(let groupID, let elementID):
            switch try codec.openTopicMessage(SyncElementPayload.self, from: message.payload) {
            case .content(let payload):
                summary.elementStamps[elementID] = payload.updatedAt
                return store.applyRemoteElement(payload.toElement(), groupID: groupID, collectionID: collectionID) == .deferred
            case .tombstone(let stone):
                summary.elementStamps[elementID] = stone.deletedAt
                summary.tombstonedElementIDs.insert(elementID)
                _ = store.applyRemoteElementTombstone(elementID: elementID, groupID: groupID, collectionID: collectionID,
                                                      deletedAt: stone.deletedAt, by: stone.by)
            }

        case .claim(let elementID):
            if message.payload.isEmpty {
                // The one legitimate empty retained payload: released. (In replay, a
                // cleared retained topic simply never arrives — this is the live path.)
                if case .freed(let element) = store.applyRemoteClaim(nil, claimantName: "", elementID: elementID,
                                                                     collectionID: collectionID, selfID: selfMemberID) {
                    onEvent?(.elementFreed(element))
                }
                return false
            }
            let payload = try codec.open(SyncClaimPayload.self, from: message.payload)
            summary.claims[elementID] = payload.memberID
            let claim = NBClaim(who: payload.memberID, claimedAt: payload.at)
            return store.applyRemoteClaim(claim, claimantName: payload.name, elementID: elementID,
                                          collectionID: collectionID, selfID: selfMemberID) == .deferred

        case .presence(let memberID):
            guard memberID != selfMemberID else { return false }
            let payload = try codec.open(SyncPresencePayload.self, from: message.payload)
            applyPresence(memberID: memberID, payload: payload)

        case .syncBarrier:
            break
        }
        return false
    }

    private func applyPresence(memberID: String, payload: SyncPresencePayload) {
        // Presence also introduces the member, so names render before their first claim.
        if let workspace = currentWorkspace, workspace.members[memberID]?.name != payload.name {
            var members = workspace.members
            members[memberID] = NBMember(id: memberID, name: payload.name)
            setMembers(members)
        }

        var online = onlineMemberIDs
        switch payload.state {
        case .online: online.insert(memberID)
        case .offline: online.remove(memberID)
        }
        guard online != onlineMemberIDs else { return }

        // Going offline renders that member's claims free — notify watchers. Data stays
        // untouched: the mark survives and re-renders "in use" when they return.
        if payload.state == .offline, let workspace = currentWorkspace {
            for group in workspace.groups.values {
                for element in group.elements where element.claimedBy?.who == memberID {
                    onEvent?(.elementFreed(element))
                }
            }
        }
        setOnlineMembers(online)
    }

    private func retryDeferred() {
        guard !deferred.isEmpty else { return }
        let cutoff = Date().addingTimeInterval(-Self.deferredLifetime)
        let pending = deferred
        deferred = []
        for entry in pending where entry.at >= cutoff {
            guard let topic = SyncTopic.parse(entry.message.topic, room: config.room) else { continue }
            var throwaway = ReplaySummary()
            // Still deferred? Re-buffer with the ORIGINAL arrival time, so the lifetime
            // can actually expire instead of resetting on every retry.
            if (try? applyOne(topic: topic, message: entry.message, summary: &throwaway)) == true {
                deferred.append(entry)
            }
        }
    }

    // MARK: Seeding and reconciliation

    /// The room is empty: this Mac defines it. Elements strictly before own claims — a
    /// claim on an element the room has never seen would just get dropped by peers.
    private func seedRoom() {
        guard let workspace = currentWorkspace else { return }
        publishMeta(name: workspace.name, updatedAt: workspace.nameUpdatedAt)
        for (index, groupID) in workspace.groupOrder.enumerated() {
            guard let group = workspace.groups[groupID] else { continue }
            publishSchema(group, sortIndex: index)
            for element in group.elements {
                publishElement(element, groupID: groupID)
            }
        }
        for stone in workspace.tombstones {
            publishTombstone(stone)
        }
        for group in workspace.groups.values {
            for element in group.elements where element.claimedBy?.who == selfMemberID {
                publishClaim(element.claimedBy, elementID: element.id)
            }
        }
    }

    /// Rejoining after being offline: replay has merged the room into local state, now
    /// push everything local the broker doesn't know — newer edits, new elements, offline
    /// deletions, and claims made while away.
    private func reconcilePush(against summary: ReplaySummary) {
        guard let workspace = currentWorkspace else { return }

        for (index, groupID) in workspace.groupOrder.enumerated() {
            guard let group = workspace.groups[groupID] else { continue }
            if let brokerStamp = summary.schemaStamps[groupID] {
                if group.updatedAt > brokerStamp { publishSchema(group, sortIndex: index) }
            } else {
                publishSchema(group, sortIndex: index)
            }
            for element in group.elements {
                if let brokerStamp = summary.elementStamps[element.id] {
                    if element.updatedAt > brokerStamp { publishElement(element, groupID: groupID) }
                } else {
                    publishElement(element, groupID: groupID)
                }
            }
        }

        // Offline deletions: the broker still holds content our tombstone beats, or has
        // never heard of the deletion at all.
        for stone in workspace.tombstones {
            let brokerStamp = summary.elementStamps[stone.id] ?? summary.schemaStamps[stone.id]
            let alreadyTombstoned = summary.tombstonedElementIDs.contains(stone.id) || summary.tombstonedGroupIDs.contains(stone.id)
            if !alreadyTombstoned, brokerStamp.map({ stone.deletedAt >= $0 }) ?? true {
                publishTombstone(stone)
            }
        }

        // Claims made while offline. (The inverse — released offline while the broker
        // retains our old claim — is deliberately NOT reconciled: the replayed claim
        // reinstates the mark and the auto-release sweep ages it out. A claim is a status
        // light; a minute of staleness beats a special-case protocol.)
        for group in workspace.groups.values {
            for element in group.elements where element.claimedBy?.who == selfMemberID {
                if summary.claims[element.id] != selfMemberID {
                    publishClaim(element.claimedBy, elementID: element.id)
                }
            }
        }
    }

    // MARK: Outbound

    /// A local change from the store's sink, mapped onto the wire.
    func publishLocalChange(_ change: SyncChange) {
        guard state == .connected else { return } // reconcile-push covers offline catch-up
        switch change {
        case .meta(_, let name, let updatedAt):
            publishMeta(name: name, updatedAt: updatedAt)
        case .schema(_, let group, let sortIndex):
            publishSchema(group, sortIndex: sortIndex)
        case .groupDeleted(_, let groupID, let elementIDs, let deletedAt):
            publishTombstone(NBTombstone(kind: .group, id: groupID, groupID: nil, deletedAt: deletedAt, by: selfMemberID))
            for elementID in elementIDs {
                // Clears, not tombstones: the group tombstone governs; these keep the
                // broker from retaining orphans forever.
                transport.publish(SyncMessage(topic: SyncTopic.element(groupID: groupID, elementID: elementID).string(room: config.room), payload: Data()))
                transport.publish(SyncMessage(topic: SyncTopic.claim(elementID: elementID).string(room: config.room), payload: Data()))
            }
        case .element(_, let groupID, let element):
            publishElement(element, groupID: groupID)
        case .elementDeleted(_, let groupID, let elementID, let deletedAt):
            publishTombstone(NBTombstone(kind: .element, id: elementID, groupID: groupID, deletedAt: deletedAt, by: selfMemberID))
            transport.publish(SyncMessage(topic: SyncTopic.claim(elementID: elementID).string(room: config.room), payload: Data()))
        case .claim(_, let elementID, let claim, _):
            publishClaim(claim, elementID: elementID)
        }
    }

    private func publishMeta(name: String, updatedAt: Date) {
        publishSealed(SyncMetaPayload(name: name, updatedAt: updatedAt, by: selfMemberID), to: .meta)
    }

    private func publishSchema(_ group: NBGroup, sortIndex: Int) {
        publishSealed(SyncSchemaPayload(group: group, sortIndex: sortIndex, by: selfMemberID), to: .schema(groupID: group.id))
    }

    private func publishElement(_ element: NBElement, groupID: String) {
        publishSealed(SyncElementPayload(element: element), to: .element(groupID: groupID, elementID: element.id))
    }

    private func publishClaim(_ claim: NBClaim?, elementID: String) {
        guard let claim else {
            // Released: clear the retained claim — empty topic IS the free state.
            transport.publish(SyncMessage(topic: SyncTopic.claim(elementID: elementID).string(room: config.room), payload: Data()))
            return
        }
        publishSealed(SyncClaimPayload(memberID: claim.who, name: selfName.isEmpty ? "someone" : selfName, at: claim.claimedAt),
                      to: .claim(elementID: elementID))
    }

    private func publishTombstone(_ stone: NBTombstone) {
        let payload = SyncTombstonePayload(deletedAt: stone.deletedAt, by: stone.by)
        let topic: SyncTopic = stone.kind == .group
            ? .schema(groupID: stone.id)
            : .element(groupID: stone.groupID ?? "", elementID: stone.id)
        publishSealed(payload, to: topic, expirySeconds: UInt32(NBTombstone.retention))
    }

    private func publishSealed<T: Encodable>(_ payload: T, to topic: SyncTopic, expirySeconds: UInt32? = nil) {
        do {
            let sealed = try codec.seal(payload)
            transport.publish(SyncMessage(topic: topic.string(room: config.room), payload: sealed, expirySeconds: expirySeconds))
        } catch {
            Self.logger.error("failed to seal payload for \(topic.string(room: self.config.room), privacy: .public): \(error)")
        }
    }

    private func presenceMessage(_ presenceState: SyncPresencePayload.State) -> SyncMessage {
        let payload = SyncPresencePayload(name: selfName.isEmpty ? "someone" : selfName, state: presenceState, at: Date())
        let topic = SyncTopic.presence(memberID: selfMemberID).string(room: config.room)
        guard let sealed = try? codec.seal(payload) else {
            return SyncMessage(topic: topic, payload: Data())
        }
        return SyncMessage(topic: topic, payload: sealed)
    }

    // MARK: Guarded writes (the tracker rule)

    private func setState(_ new: SyncConnectionState) {
        guard state != new else { return }
        state = new
    }

    private func setOnlineMembers(_ new: Set<String>) {
        guard onlineMemberIDs != new else { return }
        onlineMemberIDs = new
    }

    private var currentWorkspace: NBWorkspace? {
        store.collections.first { $0.id == collectionID }?.workspace
    }

    private func setMembers(_ members: [String: NBMember]) {
        guard let cIndex = store.collections.firstIndex(where: { $0.id == collectionID }) else { return }
        store.collections[cIndex].workspace.members = members
    }
}

// MARK: - SyncEngine

@MainActor
final class SyncEngine {
    private(set) var sessions: [String: RoomSession] = [:]

    private let store: CollectionStore
    var selfMemberID: String
    var selfName: String
    /// How a session gets its transport — the loopback broker in tests, MQTT in the app.
    /// The second argument is the broker account's password, already unsealed (nil for
    /// brokers without auth) — the engine owns the seal/unseal because both need the key.
    let transportFactory: (NBRoomConfig, String?) -> SyncTransport
    /// Bubbled per-collection room events; the view model turns them into copy.
    var onEvent: ((_ collectionID: String, _ event: RoomEvent) -> Void)?

    private static let logger = Logger(subsystem: "flourix.notchboard", category: "sync")

    init(store: CollectionStore, selfMemberID: String, selfName: String,
         transportFactory: @escaping (NBRoomConfig, String?) -> SyncTransport) {
        self.store = store
        self.selfMemberID = selfMemberID
        self.selfName = selfName
        self.transportFactory = transportFactory
    }

    func session(for collectionID: String) -> RoomSession? {
        sessions[collectionID]
    }

    /// Wired as `store.changeSink` (weakly — the store must not retain the engine that
    /// retains sessions that retain the store).
    func handleLocalChange(_ change: SyncChange) {
        sessions[change.collectionID]?.publishLocalChange(change)
    }

    /// Joins (or rejoins) a room. Key derivation runs at full PBKDF2 cost off the main
    /// actor; `preDerivedKey` short-circuits it for tests, which need determinism more
    /// than they need the stretch.
    ///
    /// `brokerPassword` is the plaintext broker-account password, passed exactly once —
    /// at the setup moment, by whoever typed it. The engine seals it under the room key
    /// into the stored config, so every later join (relaunch, an invitee, an importer)
    /// finds it there and unseals it instead. That asymmetry is the whole "one password
    /// to join" design: the credential travels sealed, nobody retypes it.
    func joinRoom(_ config: NBRoomConfig, password: String, collectionID: String,
                  brokerPassword: String? = nil,
                  rounds: Int = TransferCrypto.defaultRounds, preDerivedKey: SymmetricKey? = nil) {
        guard let host = config.brokerHost else {
            onEvent?(collectionID, .failed("\(config.brokerURL) isn't a usable broker address"))
            return
        }
        leaveRoom(collectionID: collectionID)

        if let preDerivedKey {
            startSession(config, collectionID: collectionID, key: preDerivedKey, plaintextBrokerPassword: brokerPassword)
            return
        }
        let room = config.room
        Task { [weak self] in
            // The stretch is CPU-bound and deliberately slow — off the main actor.
            let derived = await Task.detached(priority: .userInitiated) {
                try? RoomCrypto.deriveKey(password: password, brokerHost: host, room: room, rounds: rounds)
            }.value
            guard let self else { return }
            guard let derived else {
                self.onEvent?(collectionID, .failed("couldn't derive the room key"))
                return
            }
            self.startSession(config, collectionID: collectionID, key: derived, plaintextBrokerPassword: brokerPassword)
        }
    }

    private func startSession(_ config: NBRoomConfig, collectionID: String, key: SymmetricKey,
                              plaintextBrokerPassword: String?) {
        var config = config
        var brokerPassword = plaintextBrokerPassword
        if let plaintext = plaintextBrokerPassword {
            guard let sealed = try? RoomCrypto.seal(Data(plaintext.utf8), key: key) else {
                onEvent?(collectionID, .failed("couldn't seal the broker password"))
                return
            }
            config.sealedBrokerPassword = sealed
        } else if let sealed = config.sealedBrokerPassword {
            // GCM authenticates, so a failed open is certain: the typed room password
            // doesn't match the one the credential was sealed under — wrong, or rotated
            // since the invite was minted. Fail before any connection attempt, and never
            // hand the broker a password we know is garbage.
            guard let opened = try? RoomCrypto.open(sealed, key: key),
                  let text = String(data: opened, encoding: .utf8) else {
                onEvent?(collectionID, .wrongPassword)
                return
            }
            brokerPassword = text
        }
        let session = RoomSession(
            collectionID: collectionID, config: config,
            transport: transportFactory(config, brokerPassword), store: store,
            key: key, selfMemberID: selfMemberID, selfName: selfName
        )
        session.onEvent = { [weak self] event in
            self?.onEvent?(collectionID, event)
        }
        sessions[collectionID] = session
        store.setRoomConfig(config, collectionID: collectionID)
        session.connect()
    }

    func leaveRoom(collectionID: String) {
        sessions[collectionID]?.suspend()
        sessions[collectionID] = nil
    }

    /// Lid closing: say goodbye properly so presence flips without waiting for the will.
    func sleepAll() {
        for session in sessions.values {
            session.suspend()
        }
    }

    func wakeAll() {
        for session in sessions.values {
            session.resume()
        }
    }
}
