//
//  PassphraseGenerator.swift
//  notchboard
//
//  One-click strong passwords (vision.md §14.5.3). Wherever the app asks for a password —
//  the export prompt today, room creation when rooms land — "generate" must be one click
//  closer than typing "team123", because the password doubles as key material for the
//  AES-GCM envelope and a weak one weakens the crypto, not just the lock.
//

import Foundation
import Security

enum PassphraseGenerator {
    /// Unambiguous lowercase alphabet: no i/l/o/0/1, so a passphrase read over a call or
    /// retyped from a screenshot can't be mis-transcribed.
    private static let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")

    /// Four dash-separated groups of five symbols, e.g. "kw3ph-x87mn-qv2tc-e9rju".
    /// 20 symbols from a 30-symbol alphabet ≈ 98 bits of entropy.
    static func generate() -> String {
        let symbols = (0..<20).map { _ in alphabet[randomIndex(below: alphabet.count)] }
        return stride(from: 0, to: symbols.count, by: 5)
            .map { String(symbols[$0..<Swift.min($0 + 5, symbols.count)]) }
            .joined(separator: "-")
    }

    /// Unbiased index from the system CSPRNG — rejection-sampled so `count` doesn't have
    /// to divide 256 evenly.
    private static func randomIndex(below count: Int) -> Int {
        let limit = UInt8(256 - (256 % count))
        while true {
            var byte: UInt8 = 0
            let status = withUnsafeMutableBytes(of: &byte) {
                SecRandomCopyBytes(kSecRandomDefault, 1, $0.baseAddress!)
            }
            // SecRandomCopyBytes failing is effectively "the OS is broken"; arc4random's
            // pool is the same CSPRNG family and never fails, so fall back rather than trap.
            guard status == errSecSuccess else { return Int(arc4random_uniform(UInt32(count))) }
            if byte < limit { return Int(byte) % count }
        }
    }
}
