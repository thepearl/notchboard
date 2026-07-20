//
//  NotchboardViewModel.swift
//  notchboard
//
//  Drives all interaction state for the UI/UX prototype layer — mirrors the state machine
//  in Notchboard Prototype.dc.html. No networking/backend yet (see vision.md §9).
//

import Foundation
import Observation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

enum NotchboardPanelView: Equatable {
    case list
    case detail(elementID: String)
    case add
    case newGroup
}

@Observable
final class NotchboardViewModel {
    // MARK: Chrome
    var isExpanded: Bool = true
    var showCoachMark: Bool = false

    // MARK: Data
    var workspace: NBWorkspace = MockData.workspace()

    // MARK: Navigation / filters
    var activeGroupID: String = "users"
    var currentView: NotchboardPanelView = .list
    var environmentFilter: NBEnvironment = .all
    var searchText: String = ""
    var tooltipElementID: String?
    var revealedFieldKeys: Set<String> = [] // key = "\(elementID).\(fieldKey)"

    // MARK: Add-element form
    var addName: String = ""
    var addEnvironment: NBEnvironment = .dev
    var addNote: String = ""
    var addValues: [String: String] = [:]

    // MARK: New-group form
    var newGroupName: String = ""
    var newGroupFields: [NBField] = [
        NBField(key: "name", label: "name", type: .text),
        NBField(key: "value", label: "value", type: .text),
    ]

    // MARK: Toasts
    var toasts: [NBToast] = []

    // MARK: Settings (mirrors the prototype's configurable props)
    var autoReleaseMinutes: Int = 60
    var startExpanded: Bool = true
    var liveSyncEnabled: Bool = true

    // MARK: Global shortcuts (⌘K / ⌘N — see AppDelegate's global NSEvent monitor)
    /// Bumped whenever the global ⌘K shortcut fires; the search field observes this and
    /// grabs focus. A counter (rather than a bool) so repeated presses always re-trigger it.
    var searchFocusToken: Int = 0

    /// Periodically frees claims older than `autoReleaseMinutes` (the behaviour the
    /// Settings surface advertises). 30s granularity is plenty for a minutes-based limit.
    @ObservationIgnored private var autoReleaseTimer: Timer?

    init() {
        autoReleaseTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.releaseExpiredClaims()
        }
    }

    deinit {
        autoReleaseTimer?.invalidate()
    }

    /// Builds a snapshot of everything worth persisting between launches.
    func persistableState(onboardingCompleted: Bool, onboardingName: String) -> PersistedAppState {
        PersistedAppState(
            workspace: workspace,
            autoReleaseMinutes: autoReleaseMinutes,
            startExpanded: startExpanded,
            liveSyncEnabled: liveSyncEnabled,
            onboardingCompleted: onboardingCompleted,
            onboardingName: onboardingName
        )
    }

    /// Restores settings + data from a previous session (called once at launch).
    /// Persisted state is user-editable JSON on disk, so it's sanitised here rather than
    /// trusted: `groupOrder`/`groups` are reconciled, and an unusable workspace falls back
    /// to fresh seed data instead of stranding (or crashing) the UI.
    func restore(from persisted: PersistedAppState) {
        var restored = persisted.workspace
        restored.groupOrder.removeAll { restored.groups[$0] == nil }
        let unordered = restored.groups.keys.filter { !restored.groupOrder.contains($0) }.sorted()
        restored.groupOrder.append(contentsOf: unordered)
        if restored.groups.isEmpty {
            restored = MockData.workspace()
        }

        workspace = restored
        if workspace.groups[activeGroupID] == nil {
            activeGroupID = workspace.groupOrder.first ?? ""
        }
        autoReleaseMinutes = persisted.autoReleaseMinutes
        startExpanded = persisted.startExpanded
        liveSyncEnabled = persisted.liveSyncEnabled
        isExpanded = persisted.startExpanded
    }

    // MARK: - Derived

    var activeGroup: NBGroup {
        if let group = workspace.groups[activeGroupID] { return group }
        if let firstID = workspace.groupOrder.first, let group = workspace.groups[firstID] { return group }
        // Read on nearly every render — an inconsistent workspace must degrade to an empty
        // group, never trap.
        return NBGroup(id: "", label: "elements", singular: "element", secondaryKey: "", fields: [], elements: [])
    }

    var claimedCount: Int {
        workspace.groupOrder.reduce(0) { total, id in
            total + (workspace.groups[id]?.elements.filter(\.isClaimed).count ?? 0)
        }
    }

    var filteredElements: [NBElement] {
        let group = activeGroup
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = group.elements.filter { element in
            let envMatches = environmentFilter == .all || element.env == environmentFilter
            guard envMatches else { return false }
            guard !query.isEmpty else { return true }
            let haystack = ([element.name, element.note] + Array(element.values.values))
                .joined(separator: " ")
                .lowercased()
            return haystack.contains(query)
        }
        return filtered.sorted { ($0.isFavorite ? 1 : 0) > ($1.isFavorite ? 1 : 0) }
    }

    func secondaryText(for element: NBElement, in group: NBGroup) -> String {
        // Special-cased formats only apply when the schema actually carries those fields —
        // group IDs alone aren't a contract once users create their own groups.
        if group.id == "promos", let pct = element.values["discount_pct"] {
            return "\(pct)% off · exp \(element.values["expires"] ?? "—")"
        }
        if group.id == "products", let sku = element.values["sku"] {
            return "\(sku) · €\(element.values["price"] ?? "")"
        }
        return element.values[group.secondaryKey] ?? ""
    }

    func memberName(_ who: String) -> String {
        who == "you" ? "You" : (workspace.members[who]?.name ?? who)
    }

    func selectedElement(id: String) -> NBElement? {
        activeGroup.elements.first { $0.id == id }
    }

    // MARK: - Actions: navigation

    func openDetail(_ element: NBElement) {
        tooltipElementID = nil
        currentView = .detail(elementID: element.id)
    }

    func backToList() {
        currentView = .list
    }

    func openAdd() {
        addName = ""
        addValues = [:]
        addNote = ""
        addEnvironment = .dev
        currentView = .add
    }

    func openNewGroup() {
        newGroupName = ""
        newGroupFields = [
            NBField(key: "name", label: "name", type: .text),
            NBField(key: "value", label: "value", type: .text),
        ]
        currentView = .newGroup
    }

    func selectGroup(_ id: String) {
        activeGroupID = id
        currentView = .list
    }

    func toggleExpanded() {
        isExpanded.toggle()
        showCoachMark = false
    }

    // MARK: - Actions: element mutation

    func toggleFavorite(_ elementID: String) {
        mutate(elementID) { $0.isFavorite.toggle() }
    }

    func claimOrRelease(_ elementID: String) {
        guard var group = workspace.groups[activeGroupID],
              let idx = group.elements.firstIndex(where: { $0.id == elementID }) else { return }
        let element = group.elements[idx]

        if let claim = element.claimedBy {
            if claim.who == "you" {
                group.elements[idx].claimedBy = nil
                workspace.groups[activeGroupID] = group
                toast("released “\(element.name)”", color: .green)
            } else {
                toast("\(memberName(claim.who)) has this — ping them or claim anyway", color: .red)
            }
        } else {
            group.elements[idx].claimedBy = NBClaim(who: "you")
            workspace.groups[activeGroupID] = group
            copyPrimaryField(of: element)
        }
    }

    func toggleReveal(elementID: String, fieldKey: String) {
        let key = "\(elementID).\(fieldKey)"
        if revealedFieldKeys.contains(key) {
            revealedFieldKeys.remove(key)
        } else {
            revealedFieldKeys.insert(key)
        }
    }

    func isRevealed(elementID: String, fieldKey: String) -> Bool {
        revealedFieldKeys.contains("\(elementID).\(fieldKey)")
    }

    func notifyWhenFree(_ element: NBElement) {
        toast("you'll be pinged when “\(element.name)” is free", color: .green)
    }

    func copy(_ text: String, label: String, concealed: Bool = false) {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if concealed {
            // Standard hint (nspasteboard.org) telling clipboard managers not to record
            // this entry — used for secret-typed field values.
            pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        }
        #endif
        toast("\(label) copied to clipboard", color: .amber)
    }

    /// Copies an element's primary (first schema) field — the row copy button and the
    /// claim-and-copy flow share this so the "what is primary" logic lives in one place.
    func copyPrimaryField(of element: NBElement) {
        let field = activeGroup.fields.first
        copy(
            element.values[field?.key ?? ""] ?? element.name,
            label: field?.label ?? "value",
            concealed: field?.type == .secret
        )
    }

    private func releaseExpiredClaims() {
        let limit = autoReleaseMinutes
        for groupID in workspace.groupOrder {
            guard var group = workspace.groups[groupID] else { continue }
            var changed = false
            for idx in group.elements.indices {
                guard let claim = group.elements[idx].claimedBy, claim.minutesAgo >= limit else { continue }
                group.elements[idx].claimedBy = nil
                changed = true
                toast("auto-released “\(group.elements[idx].name)” after \(limit)m idle", color: .green)
            }
            if changed { workspace.groups[groupID] = group }
        }
    }

    private func mutate(_ elementID: String, _ change: (inout NBElement) -> Void) {
        guard var group = workspace.groups[activeGroupID],
              let idx = group.elements.firstIndex(where: { $0.id == elementID }) else { return }
        change(&group.elements[idx])
        workspace.groups[activeGroupID] = group
    }

    // MARK: - Actions: add element

    func createElement() {
        let trimmedName = addName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            toast("give it a display name first", color: .red)
            return
        }
        let element = NBElement(
            id: UUID().uuidString,
            name: trimmedName, env: addEnvironment, isFavorite: false, claimedBy: nil,
            note: addNote.trimmingCharacters(in: .whitespacesAndNewlines),
            lastUsed: "just now, by you", values: addValues
        )
        var group = activeGroup
        group.elements.append(element)
        workspace.groups[activeGroupID] = group
        currentView = .list
        toast("“\(element.name)” added · synced to team", color: .green)
    }

    // MARK: - Actions: new group

    func addNewGroupField() {
        newGroupFields.append(NBField(key: "field_\(newGroupFields.count + 1)", label: "field_\(newGroupFields.count + 1)", type: .text))
    }

    func removeNewGroupField(_ id: UUID) {
        newGroupFields.removeAll { $0.id == id }
    }

    func createGroup() {
        let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            toast("name the group first", color: .red)
            return
        }
        let groupID = name.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
        guard workspace.groups[groupID] == nil else {
            toast("group already exists", color: .red)
            return
        }
        let fields = newGroupFields
            .filter { !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { field -> NBField in
                var f = field
                f.key = field.label.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
                return f
            }
        guard let firstField = fields.first else {
            toast("add at least one field", color: .red)
            return
        }
        let group = NBGroup(
            id: groupID, label: name.lowercased(),
            singular: name.lowercased().hasSuffix("s") ? String(name.lowercased().dropLast()) : name.lowercased(),
            secondaryKey: firstField.key, fields: fields, elements: []
        )
        workspace.groups[groupID] = group
        workspace.groupOrder.append(groupID)
        activeGroupID = groupID
        currentView = .list
        toast("group “\(name)” created · template synced", color: .green)
    }

    // MARK: - Toasts

    func toast(_ message: String, color: NBToastColor) {
        let item = NBToast(id: UUID(), message: message, color: color)
        toasts.append(item)
        if toasts.count > 4 { toasts.removeFirst(toasts.count - 4) }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            self?.toasts.removeAll { $0.id == item.id }
        }
    }

    // MARK: - Onboarding replay

    func replayOnboarding() {
        // Handled by parent scene; view model just resets panel state.
        currentView = .list
        showCoachMark = false
    }
}

struct NBToast: Identifiable, Equatable {
    let id: UUID
    let message: String
    let color: NBToastColor
}

enum NBToastColor {
    case amber, green, red

    var color: Color {
        switch self {
        case .amber: return NBColor.amber
        case .green: return NBColor.green
        case .red: return NBColor.red
        }
    }
}
