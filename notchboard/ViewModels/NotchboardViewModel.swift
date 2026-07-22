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
    /// The row highlighted for keyboard navigation in the list (arrows/return). Distinct
    /// from the tooltip and from the open detail view.
    var keyboardSelectionID: String?
    var revealedFieldKeys: Set<String> = [] // key = "\(elementID).\(fieldKey)"
    /// Elements the user asked to be pinged about when they become free. Cleared once the
    /// notification fires. In-memory only — a watch doesn't outlive the session.
    @ObservationIgnored private var watchedElementIDs: Set<String> = []

    // MARK: Add/edit-element form
    /// Non-nil while the add form is editing an existing element instead of creating one.
    var editingElementID: String?
    var addName: String = ""
    var addEnvironment: NBEnvironment = .dev
    var addNote: String = ""
    var addValues: [String: String] = [:]

    // MARK: New/edit-group form
    /// Non-nil while the group form is editing an existing group instead of creating one.
    var editingGroupID: String?
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
    /// The target app's debug URL scheme for "login on sim" — e.g. "brewly" fires
    /// brewly://debug/login?user=…. Empty means the deeplink bridge is unconfigured.
    var deeplinkScheme: String = ""
    /// Which edge of the Simulator window the notch/panel docks to.
    var dockEdge: NBDockEdge = .right

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
            deeplinkScheme: deeplinkScheme,
            dockEdge: dockEdge,
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
        restored.reconcileGroupOrder()
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
        deeplinkScheme = persisted.deeplinkScheme
        dockEdge = persisted.dockEdge
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
        editingElementID = nil
        addName = ""
        addValues = [:]
        addNote = ""
        addEnvironment = .dev
        currentView = .add
    }

    /// Opens the element form prefilled for editing — same form as `openAdd`, save updates
    /// in place instead of creating.
    func openEdit(_ element: NBElement) {
        editingElementID = element.id
        addName = element.name
        // Preserve the element's env exactly (including .all) rather than coercing to .dev —
        // saveElement writes this back, so a coercion here would silently mutate the env of
        // any element edited for an unrelated reason.
        addEnvironment = element.env
        addNote = element.note
        addValues = element.values
        currentView = .add
    }

    func openNewGroup() {
        editingGroupID = nil
        newGroupName = ""
        newGroupFields = [
            NBField(key: "name", label: "name", type: .text),
            NBField(key: "value", label: "value", type: .text),
        ]
        currentView = .newGroup
    }

    /// Opens the group form prefilled with the active group's name and schema.
    func openEditGroup() {
        let group = activeGroup
        guard !group.id.isEmpty else { return }
        editingGroupID = group.id
        newGroupName = group.label
        newGroupFields = group.fields
        currentView = .newGroup
    }

    func selectGroup(_ id: String) {
        activeGroupID = id
        currentView = .list
        keyboardSelectionID = nil
    }

    // MARK: - Actions: keyboard navigation (list view)

    /// Moves the keyboard highlight up (-1) or down (+1) through the currently filtered
    /// rows, clamping at the ends and starting from the top/bottom when nothing is selected.
    func moveKeyboardSelection(_ delta: Int) {
        let elements = filteredElements
        guard !elements.isEmpty else { return }
        let currentIndex = elements.firstIndex { $0.id == keyboardSelectionID }
        let nextIndex: Int
        if let currentIndex {
            nextIndex = min(max(currentIndex + delta, 0), elements.count - 1)
        } else {
            nextIndex = delta > 0 ? 0 : elements.count - 1
        }
        keyboardSelectionID = elements[nextIndex].id
    }

    /// Opens the keyboard-highlighted row (Return). Returns false if nothing is highlighted,
    /// so the caller can let the key fall through.
    @discardableResult
    func openKeyboardSelection() -> Bool {
        guard let id = keyboardSelectionID, let element = filteredElements.first(where: { $0.id == id }) else {
            return false
        }
        openDetail(element)
        return true
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
                didFreeElement(group.elements[idx])
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
        watchedElementIDs.insert(element.id)
        toast("you'll be pinged when “\(element.name)” is free", color: .green)
    }

    /// Called whenever an element's claim is cleared (manual release or auto-release). If it
    /// was being watched, fire a local notification and drop the watch.
    private func didFreeElement(_ element: NBElement) {
        guard watchedElementIDs.remove(element.id) != nil else { return }
        Notifier.notifyElementFree(name: element.name)
        toast("“\(element.name)” is now free", color: .green)
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

    // MARK: - Actions: deeplink bridge ("login on sim")

    /// The username to fire in the debug-login deeplink, or nil when this element can't
    /// log in (schema has no username field, or the value is empty). Schema-driven — any
    /// group whose elements carry a "username" gets the button, not just the seed "users".
    func loginUsername(for element: NBElement) -> String? {
        guard let username = element.values["username"], !username.isEmpty else { return nil }
        return username
    }

    /// The password for an auth element: the value of the group's first secret-typed field.
    /// Read in-memory (real value, not the on-disk placeholder). Nil if no secret field or
    /// the value is empty.
    func loginPassword(for element: NBElement) -> String? {
        guard let key = activeGroup.secretFieldKeys.first,
              let password = element.values[key], !password.isEmpty else { return nil }
        return password
    }

    /// True when an element carries enough to be treated as an auth credential — a username
    /// plus a secret. Drives the auth-specific buttons (deeplink + copy-and-claim).
    func isAuthElement(_ element: NBElement) -> Bool {
        loginUsername(for: element) != nil && loginPassword(for: element) != nil
    }

    func loginOnSim(_ element: NBElement) {
        guard let username = loginUsername(for: element) else { return }
        let scheme = deeplinkScheme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scheme.isEmpty else {
            toast("set your app's debug URL scheme in settings first", color: .red)
            return
        }
        guard let encodedUser = username.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return }

        var query = "user=\(encodedUser)"
        // Pass the password too when the element has one, so the target app can fill both
        // fields. Username-only apps simply ignore the extra param.
        if let password = loginPassword(for: element),
           let encodedPass = password.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            query += "&pass=\(encodedPass)"
        }

        let wasFree = element.claimedBy == nil
        SimctlBridge.openURL("\(scheme)://debug/login?\(query)") { [weak self] failure in
            guard let self else { return }
            if let failure {
                // The deeplink never fired — don't leave the element falsely claimed.
                self.toast(failure.userMessage, color: .red)
                return
            }
            // Logging in as this account is de facto using it — auto-claim if it was free
            // (vision §5.3), but only now that the deeplink actually succeeded.
            if wasFree, self.selectedElement(id: element.id)?.claimedBy == nil {
                self.mutate(element.id) { $0.claimedBy = NBClaim(who: "you") }
            }
            self.toast("⚡ logged in as “\(element.name)” on simulator", color: .green)
        }
    }

    /// Copies an auth element's login and password to the clipboard (concealed) and marks
    /// the element as in use. This is the fallback for logins the deeplink can't drive —
    /// WebView/SSO screens (Okta and the like) — where the user pastes the credentials by
    /// hand but still wants the element claimed so teammates don't collide. Release is the
    /// normal manual claim/release action.
    func copyAuthAndClaim(_ element: NBElement) {
        let login = loginUsername(for: element) ?? element.name
        let clipboard: String
        if let password = loginPassword(for: element) {
            clipboard = "\(login)\n\(password)"
            copy(clipboard, label: "login + password", concealed: true)
        } else {
            copy(login, label: "login")
        }

        switch selectedElement(id: element.id)?.claimedBy?.who {
        case nil:
            mutate(element.id) { $0.claimedBy = NBClaim(who: "you") }
            toast("marked “\(element.name)” in use", color: .green)
        case "you":
            break // already yours; the copy toast is enough
        case .some(let who):
            toast("\(memberName(who)) has this — coordinate before using", color: .amber)
        }
    }

    private func releaseExpiredClaims() {
        let limit = autoReleaseMinutes
        for groupID in workspace.groupOrder {
            guard var group = workspace.groups[groupID] else { continue }
            var changed = false
            for idx in group.elements.indices {
                // Only auto-release your own idle claims — the manual path already refuses to
                // release someone else's, and other members' claim ages are simulated/frozen
                // in this local build, so sweeping them would be meaningless churn.
                guard let claim = group.elements[idx].claimedBy,
                      claim.who == "you", claim.minutesAgo >= limit else { continue }
                group.elements[idx].claimedBy = nil
                changed = true
                didFreeElement(group.elements[idx])
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

    // MARK: - Actions: add/edit element

    func saveElement() {
        let trimmedName = addName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            toast("give it a display name first", color: .red)
            return
        }

        if let editingID = editingElementID {
            mutate(editingID) { element in
                element.name = trimmedName
                element.env = addEnvironment
                element.note = addNote.trimmingCharacters(in: .whitespacesAndNewlines)
                element.values = addValues
            }
            editingElementID = nil
            currentView = .detail(elementID: editingID)
            toast("“\(trimmedName)” updated · synced to team", color: .green)
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

    func deleteElement(_ elementID: String) {
        guard var group = workspace.groups[activeGroupID],
              let idx = group.elements.firstIndex(where: { $0.id == elementID }) else { return }
        let element = group.elements.remove(at: idx)
        workspace.groups[activeGroupID] = group

        // The persisted JSON only ever held placeholders; the real secret values live in
        // the Keychain and must be cleaned up with the element.
        for key in group.secretFieldKeys {
            SecretsStore.delete(for: "\(element.id).\(key)")
        }
        revealedFieldKeys = revealedFieldKeys.filter { !$0.hasPrefix("\(elementID).") }
        watchedElementIDs.remove(elementID)

        currentView = .list
        toast("“\(element.name)” deleted", color: .red)
    }

    // MARK: - Actions: new/edit group

    func addNewGroupField() {
        newGroupFields.append(NBField(key: "field_\(newGroupFields.count + 1)", label: "field_\(newGroupFields.count + 1)", type: .text))
    }

    func removeNewGroupField(_ id: UUID) {
        newGroupFields.removeAll { $0.id == id }
    }

    func saveGroup() {
        let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            toast("name the group first", color: .red)
            return
        }

        if let editingID = editingGroupID {
            updateGroup(editingID, name: name)
            return
        }

        let groupID = Self.slug(name)
        guard workspace.groups[groupID] == nil else {
            toast("group already exists", color: .red)
            return
        }
        let fields = newGroupFields
            .filter { !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { field -> NBField in
                var f = field
                f.key = Self.slug(field.label)
                return f
            }
        guard let firstField = fields.first else {
            toast("add at least one field", color: .red)
            return
        }
        let group = NBGroup(
            id: groupID, label: name.lowercased(),
            singular: Self.singularise(name),
            secondaryKey: firstField.key, fields: fields, elements: []
        )
        workspace.groups[groupID] = group
        workspace.groupOrder.append(groupID)
        activeGroupID = groupID
        currentView = .list
        toast("group “\(name)” created · template synced", color: .green)
    }

    /// Applies the group form to an existing group. Fields that already existed (matched by
    /// their stable `NBField.id`) keep their `key`, so element values survive a relabel;
    /// only newly added fields derive a key from their label. Values (and Keychain secrets)
    /// of removed fields are dropped.
    private func updateGroup(_ groupID: String, name: String) {
        guard var group = workspace.groups[groupID] else { return }

        let existingByID = Dictionary(uniqueKeysWithValues: group.fields.map { ($0.id, $0) })
        var usedKeys = Set<String>()
        var fields: [NBField] = []
        for field in newGroupFields where !field.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var f = field
            f.key = existingByID[field.id]?.key ?? Self.slug(field.label)
            while usedKeys.contains(f.key) { f.key += "_" }
            usedKeys.insert(f.key)
            fields.append(f)
        }
        guard let firstField = fields.first else {
            toast("add at least one field", color: .red)
            return
        }

        // A field that was a secret but is no longer one in the new schema — whether it was
        // removed OR retyped to a non-secret type — must have its value dropped and its
        // Keychain entry deleted. Otherwise the previously-protected value would survive in
        // memory and get written to state.json in cleartext on the next save.
        let keptKeys = Set(fields.map(\.key))
        let newSecretKeys = Set(fields.filter { $0.type == .secret }.map(\.key))
        let clearedSecretKeys = Set(group.secretFieldKeys).subtracting(newSecretKeys)
        for idx in group.elements.indices {
            group.elements[idx].values = group.elements[idx].values.filter {
                keptKeys.contains($0.key) && !clearedSecretKeys.contains($0.key)
            }
        }
        for element in group.elements {
            for key in clearedSecretKeys {
                SecretsStore.delete(for: "\(element.id).\(key)")
            }
        }

        group.label = name.lowercased()
        group.singular = Self.singularise(name)
        group.fields = fields
        group.secondaryKey = firstField.key
        workspace.groups[groupID] = group

        editingGroupID = nil
        currentView = .list
        toast("group “\(name)” updated", color: .green)
    }

    func deleteGroup(_ groupID: String) {
        guard let group = workspace.groups[groupID] else { return }
        for key in group.secretFieldKeys {
            for element in group.elements {
                SecretsStore.delete(for: "\(element.id).\(key)")
            }
        }
        workspace.groups.removeValue(forKey: groupID)
        workspace.groupOrder.removeAll { $0 == groupID }
        if activeGroupID == groupID {
            activeGroupID = workspace.groupOrder.first ?? ""
        }
        editingGroupID = nil
        currentView = .list
        toast("group “\(group.label)” deleted", color: .red)
    }

    // MARK: - Actions: import/export

    /// Replaces the whole catalogue with an imported one. Any secret values are freshly
    /// stripped (an export shouldn't carry them, but never trust an external file), the
    /// group order is reconciled so a malformed file can't strand the UI, and the discarded
    /// workspace's Keychain secrets are purged so they don't linger unreachable.
    func replaceWorkspace(with imported: NBWorkspace) {
        for key in workspace.allSecretKeychainKeys {
            SecretsStore.delete(for: key)
        }

        var clean = imported
        for (groupID, group) in imported.groups {
            let secretKeys = group.secretFieldKeys
            guard !secretKeys.isEmpty else { continue }
            var group = group
            for index in group.elements.indices {
                for key in secretKeys where group.elements[index].values[key] != nil {
                    group.elements[index].values[key] = ""
                }
            }
            clean.groups[groupID] = group
        }
        clean.reconcileGroupOrder()
        workspace = clean
        activeGroupID = clean.groupOrder.first ?? ""
        currentView = .list
        revealedFieldKeys = []
        keyboardSelectionID = nil
        watchedElementIDs = []
        let count = clean.groups.values.reduce(0) { $0 + $1.elements.count }
        toast("imported “\(clean.name)” · \(count) elements (secrets not included)", color: .green)
    }

    private static func slug(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
    }

    private static func singularise(_ name: String) -> String {
        let lowered = name.lowercased()
        return lowered.hasSuffix("s") ? String(lowered.dropLast()) : lowered
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
