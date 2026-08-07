//
//  RoomCrypto.swift
//  notchboard
//
//  The room key, and the seal/open primitives every room payload goes through.
//
//  Everything published to a room is ciphertext (decision 2026-08-07, amending §14.7 for
//  the wire): the broker relays bytes it cannot read, and its operator sees only topic
//  structure, sizes and timing. This deliberately diverges from the export file's
//  secrets-only split — a file is read once by someone you sent it to, a broker watches
//  the whole catalogue stream past continuously.
//
//  Key chain: room password → PBKDF2 (TransferCrypto.stretch, the shared expensive stage)
//  → HKDF with info "nb-room" (domain separation — an export password and a room
//  password that happen to be equal still yield unrelated keys) → AES-GCM per message.
//
//  The salt is deterministic — SHA256 over the broker host and room slug — because every
//  member must derive the same key with no handshake and nowhere to store a shared random
//  salt (the broker only holds what members publish, which is already encrypted). A fixed
//  salt weakens nothing against the realistic attacker (the broker operator, who knows
//  host and room anyway); what it costs is cross-room rainbow-table reuse, which the
//  per-room input already prevents. The compensating control for weak passwords is the
//  passphrase generator, one click away on every room password field (§14.5.3).
//

import CryptoKit
import Foundation

/// nonisolated: pure functions over value types — key derivation runs off the main actor
/// on purpose (PBKDF2 is deliberately slow), and the default main-actor isolation would
/// forbid exactly that.
nonisolated enum RoomCrypto {

    /// Derives the room key. Runs PBKDF2 at full cost — call it once per connect, off the
    /// main actor, and cache the result in the session.
    static func deriveKey(password: String, brokerHost: String, room: String,
                          rounds: Int = TransferCrypto.defaultRounds) throws -> SymmetricKey {
        let salt = roomSalt(brokerHost: brokerHost, room: room)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: try TransferCrypto.stretch(password: password, salt: salt, rounds: rounds),
            info: Data("nb-room".utf8),
            outputByteCount: 32
        )
    }

    static func roomSalt(brokerHost: String, room: String) -> Data {
        Data(SHA256.hash(data: Data("nb-room-salt:\(brokerHost)/\(room)".utf8)))
    }

    /// Seals one payload. The wire format is the AES-GCM combined box, raw — no JSON
    /// wrapper, nothing readable.
    static func seal(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(plaintext, using: key).combined else {
            throw TransferCrypto.CryptoError.keyDerivationFailed
        }
        return combined
    }

    /// Opens one payload. GCM authenticates, so the wrong room password is a clean,
    /// certain `wrongPassword` — never plausible garbage applied to the catalogue.
    static func open(_ sealed: Data, key: SymmetricKey) throws -> Data {
        guard let box = try? AES.GCM.SealedBox(combined: sealed) else {
            throw TransferCrypto.CryptoError.malformedEnvelope
        }
        guard let plaintext = try? AES.GCM.open(box, using: key) else {
            throw TransferCrypto.CryptoError.wrongPassword
        }
        return plaintext
    }
}
