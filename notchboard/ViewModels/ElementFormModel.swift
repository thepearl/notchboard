//
//  ElementFormModel.swift
//  notchboard
//
//  The add/edit-element form's own state. Extracted from NotchboardViewModel so
//  AddElementView depends on the handful of fields it actually edits rather than on the
//  whole app.
//
//  Saving is deliberately NOT here: it needs the catalogue, the active group's schema and
//  the toast stack, so it stays in the view model. This type owns what the user has typed
//  and the rules that apply to the typing itself.
//

import Foundation
import Observation

@Observable
final class ElementFormModel {
    /// Non-nil while editing an existing element instead of creating one.
    var editingElementID: String?
    var name: String = ""
    /// Multi-select: an element can live in several environments at once (see
    /// `NBElement.environments`). Never contains `.all`, and never empty.
    var environments: Set<NBEnvironment> = [.dev]
    var note: String = ""
    var values: [String: String] = [:]

    var isEditing: Bool { editingElementID != nil }

    /// A blank form for a new element.
    func reset() {
        editingElementID = nil
        name = ""
        environments = [.dev]
        note = ""
        values = [:]
    }

    /// Prefills from an existing element. Environments are preserved exactly rather than
    /// coerced — save writes them back, so a coercion here would silently move any element
    /// edited for an unrelated reason. One with none (a hand-edited file) opens as dev so
    /// the form is never in an unsaveable state.
    func prefill(from element: NBElement) {
        editingElementID = element.id
        name = element.name
        environments = element.environments.isEmpty ? [.dev] : element.environments
        note = element.note
        values = element.values
    }

    /// Adds or removes an environment, refusing to leave the element with none — an
    /// element that belongs nowhere can never be found by the filter. Returns false when
    /// the removal was refused, so the caller can explain why.
    @discardableResult
    func toggleEnvironment(_ env: NBEnvironment) -> Bool {
        guard env != .all else { return false }
        if environments.contains(env) {
            guard environments.count > 1 else { return false }
            environments.remove(env)
        } else {
            environments.insert(env)
        }
        return true
    }

    /// True when toggling `env` would leave production mixed with another environment.
    /// The decision lives here so it's testable without a window; the AppKit warning is
    /// the view's job (see EnvironmentWarningDialog).
    func wouldMixProduction(togglingOn env: NBEnvironment) -> Bool {
        guard env != .all else { return false }
        var candidate = environments
        if candidate.contains(env) {
            candidate.remove(env)
        } else {
            candidate.insert(env)
        }
        return candidate.contains(.prd) && candidate.count > 1
    }

    /// The trimmed values ready to persist, plus whatever is wrong with them. Returns nil
    /// for `problem` when the form is saveable.
    func validated(against fields: [NBField]) -> (name: String, note: String, problem: String?) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty {
            return (trimmedName, trimmedNote, "give it a display name first")
        }
        // The placeholder is in-band with user data in state.json: a field literally
        // holding it would be mistaken for a stripped secret on the next load and swap in
        // stale Keychain data (or nothing). Rejecting it at entry is the honest fix.
        if values.values.contains(AppStateStore.keychainPlaceholder) {
            return (trimmedName, trimmedNote, "that value is reserved by notchboard — pick another")
        }
        if environments.isEmpty {
            return (trimmedName, trimmedNote, "pick at least one environment")
        }
        // The form's controls make most wrong values hard to type, but values also arrive
        // from imports and hand-edited files — this is the gate that actually holds.
        if let problem = NBFieldValidation.firstProblem(in: values, fields: fields) {
            return (trimmedName, trimmedNote, problem)
        }
        return (trimmedName, trimmedNote, nil)
    }
}
