//
//  NBDeeplinkScheme.swift
//  notchboard
//
//  Everything about turning what a user typed into a debug-login URL, in one place because
//  three surfaces need the same answer: the collection menu (validating on entry), Settings,
//  and `loginOnSim` (validating again at fire time, since values also arrive from imports).
//
//  Pure functions on purpose — the rules here are the security boundary for the one feature
//  that puts credentials into a URL, and they should be testable without a view model.
//

import Foundation

enum NBDeeplinkScheme {
    /// Schemes that would turn the credential deeplink into a real network request. A user
    /// pasting their app's universal link ("https://app.example.com") must never end up
    /// firing username and password as query parameters at a live host.
    static let networkSchemes: Set<String> = ["http", "https", "ftp", "file", "ws", "wss"]

    /// Normalises what was typed: strips a pasted "://" and any trailing ":" / "/" / "." /
    /// whitespace, so "mythos", "mythos.", "mythos://" and "mythos:" all resolve to
    /// "mythos". A stray trailing dot silently produced an unhandled URL scheme.
    static func resolve(_ raw: String) -> String {
        var scheme = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let separator = scheme.range(of: "://") {
            scheme = String(scheme[..<separator.lowerBound])
        }
        return scheme.trimmingCharacters(in: CharacterSet(charactersIn: ":/. "))
    }

    /// True when `scheme` matches the URL-scheme grammar (a letter, then letters, digits,
    /// "+", "-" or ".") and is not a network scheme.
    static func isValid(_ scheme: String) -> Bool {
        guard !networkSchemes.contains(scheme.lowercased()) else { return false }
        guard let first = scheme.first, first.isASCII, first.isLetter else { return false }
        return scheme.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "+" || character == "-" || character == ".")
        }
    }

    /// Builds `<scheme>://debug/login?user=…[&pass=…]`, percent-encoding both values.
    /// Returns nil when the username can't be encoded at all.
    ///
    /// Encoding against `.alphanumerics` is deliberately aggressive: it escapes "@", "+"
    /// and "." in an email, and every punctuation character a generated password can carry,
    /// so nothing in a credential can terminate the query or be read as a separator.
    static func debugLoginURL(scheme: String, username: String, password: String?) -> String? {
        guard let encodedUser = username.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
            return nil
        }
        var query = "user=\(encodedUser)"
        if let password, let encodedPass = password.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            query += "&pass=\(encodedPass)"
        }
        return "\(scheme)://debug/login?\(query)"
    }
}
