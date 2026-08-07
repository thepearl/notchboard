//
//  TransferCrypto.swift
//  notchboard
//
//  Password-based sealing for the secret values inside a collection export
//  (vision.md §14.5.1). The chain is the one §14.2 documents: PBKDF2 stretches the human
//  password, HKDF domain-separates the derived key, AES-GCM seals and authenticates the
//  payload — all platform primitives (CommonCrypto + CryptoKit), no dependencies.
//
//  GCM authentication is what makes the import UX honest: a wrong password fails the tag
//  check and surfaces as `wrongPassword`, it can never decrypt into plausible garbage.
//

import CommonCrypto
import CryptoKit
import Foundation

/// The encrypted-secrets block inside an export. Salt and rounds travel with the file so
/// exports stay decryptable when the default cost rises later.
struct SecretsEnvelope: Codable, Equatable {
    var salt: Data
    var rounds: Int
    /// AES.GCM combined representation (nonce + ciphertext + tag).
    var sealed: Data
}

/// nonisolated: pure functions over value types, shared with RoomCrypto's off-main key
/// derivation — main-actor isolation would forbid the deliberate slow work moving off.
nonisolated enum TransferCrypto {
    /// PBKDF2-HMAC-SHA256 iteration count, per current OWASP guidance (600k, 2023).
    /// Costs a fraction of a second once per export/import — a modal moment, not a hot path.
    static let defaultRounds = 600_000

    enum CryptoError: Error, Equatable {
        case randomnessUnavailable
        case keyDerivationFailed
        case wrongPassword
        case malformedEnvelope
    }

    /// Seals a map of "<elementID>.<fieldKey>" → secret value under the export password.
    static func seal(_ payload: [String: String], password: String, rounds: Int = defaultRounds) throws -> SecretsEnvelope {
        var salt = Data(count: 16)
        let saltStatus = salt.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!)
        }
        guard saltStatus == errSecSuccess else { throw CryptoError.randomnessUnavailable }

        let key = try deriveKey(from: password, salt: salt, rounds: rounds)
        let plaintext = try JSONEncoder().encode(payload)
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else { throw CryptoError.keyDerivationFailed }
        return SecretsEnvelope(salt: salt, rounds: rounds, sealed: combined)
    }

    /// Opens an envelope. `wrongPassword` is the authenticated failure — the only one a
    /// user can fix; anything else means the file itself is damaged.
    static func open(_ envelope: SecretsEnvelope, password: String) throws -> [String: String] {
        // An absurd rounds value in a hand-crafted file would otherwise stall the app for
        // minutes inside PBKDF2 — cap it well above any legitimate cost.
        guard envelope.rounds > 0, envelope.rounds <= 10_000_000 else {
            throw CryptoError.malformedEnvelope
        }
        let key = try deriveKey(from: password, salt: envelope.salt, rounds: envelope.rounds)
        guard let box = try? AES.GCM.SealedBox(combined: envelope.sealed) else {
            throw CryptoError.malformedEnvelope
        }
        guard let plaintext = try? AES.GCM.open(box, using: key) else {
            throw CryptoError.wrongPassword
        }
        guard let values = try? JSONDecoder().decode([String: String].self, from: plaintext) else {
            throw CryptoError.malformedEnvelope
        }
        return values
    }

    private static func deriveKey(from password: String, salt: Data, rounds: Int) throws -> SymmetricKey {
        // HKDF binds the key to this exact purpose, so the same password+salt derivation
        // can never be reused for a different feature with an identical key — the room
        // key (RoomCrypto, info "nb-room") shares the stretch, never the key.
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: try stretch(password: password, salt: salt, rounds: rounds),
            info: Data("nb-export".utf8),
            outputByteCount: 32
        )
    }

    /// The expensive PBKDF2 stage, shared by every password-derived key in the app.
    /// Callers MUST domain-separate the result through HKDF with a purpose-specific info
    /// string — this raw stretch is never a usable key on its own.
    static func stretch(password: String, salt: Data, rounds: Int) throws -> SymmetricKey {
        var derived = Data(count: 32)
        let passwordData = Data(password.utf8)
        let status = derived.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(rounds),
                        derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw CryptoError.keyDerivationFailed }
        return SymmetricKey(data: derived)
    }
}
