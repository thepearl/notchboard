//
//  GroupFormModel.swift
//  notchboard
//
//  The new/edit-group form — the schema designer's state, plus the key-derivation rules
//  that turn typed labels into stable field keys. Extracted from NotchboardViewModel.
//
//  As with ElementFormModel, saving stays in the view model (it needs the catalogue and
//  the Keychain); what lives here is the draft and the naming rules.
//

import Foundation
import Observation

@Observable
final class GroupFormModel {
    /// Non-nil while editing an existing group instead of creating one.
    var editingGroupID: String?
    var name: String = ""
    var fields: [NBField] = GroupFormModel.starterFields

    var isEditing: Bool { editingGroupID != nil }

    /// What a brand-new group starts as: two text fields, so the designer opens with
    /// something to rename rather than an empty list.
    static var starterFields: [NBField] {
        [
            NBField(key: "name", label: "name", type: .text),
            NBField(key: "value", label: "value", type: .text),
        ]
    }

    func reset() {
        editingGroupID = nil
        name = ""
        fields = Self.starterFields
    }

    func prefill(from group: NBGroup) {
        editingGroupID = group.id
        name = group.label
        fields = group.fields
    }

    func addField() {
        let position = fields.count + 1
        fields.append(NBField(key: "field_\(position)", label: "field_\(position)", type: .text))
    }

    func removeField(_ id: UUID) {
        fields.removeAll { $0.id == id }
    }

    // MARK: - Naming rules

    /// Drops empty-labelled fields, derives keys (preserving the stable key of any field
    /// that already existed, matched by `NBField.id`), and dedupes colliding keys with a
    /// trailing underscore. Shared by the create and edit paths — they previously diverged,
    /// and the create path let "user id" and "user-id" silently share one values slot.
    static func normalisedFields(_ raw: [NBField], existingByID: [UUID: NBField] = [:]) -> [NBField] {
        var usedKeys = Set<String>()
        var fields: [NBField] = []
        for field in raw where !field.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var normalised = field
            normalised.key = existingByID[field.id]?.key ?? slug(field.label)
            while usedKeys.contains(normalised.key) { normalised.key += "_" }
            usedKeys.insert(normalised.key)
            fields.append(normalised)
        }
        return fields
    }

    static func slug(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
    }

    static func singularise(_ name: String) -> String {
        let lowered = name.lowercased()
        return lowered.hasSuffix("s") ? String(lowered.dropLast()) : lowered
    }
}
