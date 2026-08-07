//
//  NBFieldValidation.swift
//  notchboard
//
//  Makes the field types mean something. Before this, a group could declare a field as
//  `number`, `url`, `bool` or `picker` and the form would still hand you a plain text box
//  that accepted anything — the types were decoration, and a `bool` holding "yes" or a
//  `url` holding "acme dev" only surfaced later as a deeplink that didn't fire.
//
//  Two layers, deliberately: the form renders a control that makes the wrong value hard to
//  type (a toggle for bool, a picker for picker, digit filtering for number), and this
//  validator is the gate at save time — because values also arrive from imports and
//  hand-edited files, which no control can constrain.
//
//  Empty is always allowed: a blank field means "not filled in yet", not "invalid".
//

import Foundation

enum NBFieldValidation {
    /// The first problem found in `values` against `fields`, phrased for a toast, or nil
    /// when everything checks out.
    static func firstProblem(in values: [String: String], fields: [NBField]) -> String? {
        for field in fields {
            let raw = (values[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }
            if let problem = problem(with: raw, for: field) {
                return "\(field.label): \(problem)"
            }
        }
        return nil
    }

    /// What's wrong with one value for one field, or nil if it's fine. Empty is allowed
    /// here too, not only in `firstProblem` — every caller means "not filled in yet".
    static func problem(with value: String, for field: NBField) -> String? {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        switch field.type {
        case .text, .secret:
            return nil
        case .number:
            return Double(value) == nil ? "must be a number" : nil
        case .bool:
            return boolValues.contains(value.lowercased()) ? nil : "must be true or false"
        case .url:
            return isUsableURL(value) ? nil : "must be a URL, e.g. https://api.acme.dev"
        case .date:
            return dateFormatter.date(from: value) == nil ? "must be a date, e.g. 2026-12-31" : nil
        case .picker:
            guard !field.options.isEmpty else { return nil }
            return field.options.contains(value) ? nil : "must be one of: \(field.options.joined(separator: ", "))"
        }
    }

    static let boolValues = ["true", "false"]

    /// Keeps a value typeable while the user is mid-edit: strips characters the type can
    /// never accept, rather than rejecting the whole entry. Only `number` needs it — the
    /// other constrained types get a control that can't produce a wrong value.
    static func filtered(_ value: String, for type: NBFieldType) -> String {
        guard type == .number else { return value }
        var seenSeparator = false
        var seenSign = false
        return String(value.enumerated().compactMap { index, character -> Character? in
            if character.isNumber { return character }
            // One leading sign, one decimal separator — enough for prices and percentages
            // without letting "1.2.3" or "--4" through to the validator.
            if character == "-", index == 0, !seenSign { seenSign = true; return character }
            if character == ".", !seenSeparator { seenSeparator = true; return character }
            return nil
        })
    }

    /// A URL we could actually open or hand to a client: needs a scheme and a host, so
    /// "acme.dev" and "https://" are both rejected while "https://api.acme.dev/v2" passes.
    private static func isUsableURL(_ value: String) -> Bool {
        guard !value.contains(" "),
              let components = URLComponents(string: value),
              let scheme = components.scheme, !scheme.isEmpty,
              let host = components.host, !host.isEmpty else { return false }
        return true
    }

    /// ISO-style dates only. A fixed POSIX format on purpose: these values are shared
    /// between machines, so a locale-dependent parse would make the same file valid on one
    /// Mac and invalid on another.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()
}

extension NBFieldType {
    /// Placeholder copy for the add/edit form, so each type says what it wants.
    var placeholder: String {
        switch self {
        case .text: return ""
        case .secret: return "secret — masked in lists"
        case .number: return "e.g. 18.50"
        case .bool: return "true / false"
        case .date: return "YYYY-MM-DD"
        case .url: return "https://api.acme.dev"
        case .picker: return "one of the group's options"
        }
    }
}
