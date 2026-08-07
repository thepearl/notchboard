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
import os
#if canImport(AppKit)
import AppKit
#endif

private let deeplinkLog = Logger(subsystem: "flourix.notchboard", category: "deeplink")

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
    /// Set when onboarding finishes while Simulator isn't running: the coach mark is
    /// deferred until Simulator first appears instead of being silently skipped — the
    /// unexplained 28pt notch was the only thing a Simulator-less onboarder ever saw.
    var pendingCoachMark: Bool = false

    // MARK: Data
    /// Every catalogue this Mac holds — Postman-style collections (vision.md §14). Never
    /// empty: deletion refuses to remove the last one and restore falls back to seed data.
    var collections: [NBCollection]
    /// Which collection the panel is showing. Everything single-catalogue below resolves
    /// through it.
    var activeCollectionID: String

    // MARK: Identity (vision.md §14.2 — the standing prerequisite for any future sync)
    /// Stable local member id: what this user's claims are attributed to. Persisted
    /// across launches (vision.md §14.2).
    var selfMemberID: String = UUID().uuidString
    /// The onboarding display name. Labels this user's claims; empty falls back to "you".
    var selfName: String = ""

    /// The collection everything single-catalogue routes through. Falls back to the first
    /// one so a stale id degrades gracefully instead of trapping (same posture as
    /// `activeGroup`).
    var activeCollection: NBCollection {
        collections.first { $0.id == activeCollectionID }
            ?? collections.first
            ?? NBCollection(workspace: NBWorkspace(name: "", groupOrder: [], groups: [:], members: [:]))
    }

    private var activeCollectionIndex: Int? {
        collections.firstIndex { $0.id == activeCollectionID } ?? (collections.isEmpty ? nil : 0)
    }

    /// The active catalogue. A computed facade over `collections`, so the three dozen
    /// existing call sites — every one already a read-modify-write — kept compiling
    /// unchanged when one workspace became many.
    var workspace: NBWorkspace {
        get { activeCollection.workspace }
        set {
            guard let index = activeCollectionIndex else { return }
            collections[index].workspace = newValue
        }
    }

    // MARK: Navigation / filters
    var activeGroupID: String = "users"
    var currentView: NotchboardPanelView = .list
    var environmentFilter: NBEnvironment = .all
    var searchText: String = ""
    var tooltipElementID: String?
    /// Pending grace-period dismissal of the claim tooltip. The popover renders *below*
    /// the badge, so the cursor must leave the badge to reach the "notify when free"
    /// button — an immediate onLeave dismissal made that button unreachable by mouse.
    @ObservationIgnored private var tooltipDismissTask: Task<Void, Never>?
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
    /// Multi-select: an element can live in several environments at once (see
    /// `NBElement.environments`). Never contains `.all`, and never empty when saving.
    var addEnvironments: Set<NBEnvironment> = [.dev]
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
    /// Allowed auto-release window — the single definition shared by the Settings stepper
    /// and the restore-time clamp.
    static let autoReleaseRange = 5...240
    var autoReleaseMinutes: Int = 60
    var startExpanded: Bool = true
    /// The target app's debug URL scheme for "login on sim" — e.g. "brewly" fires
    /// brewly://debug/login?user=…. Per collection since Phase 2: each catalogue describes
    /// one app, so switching collections switches the app you deeplink into. Empty means
    /// the bridge is unconfigured for this collection.
    var deeplinkScheme: String {
        get { activeCollection.deeplinkScheme }
        set {
            guard let index = activeCollectionIndex else { return }
            collections[index].deeplinkScheme = newValue
        }
    }
    /// Which edge of the Simulator window the notch/panel docks to.
    var dockEdge: NBDockEdge = .right
    /// Set once the user ticks "don't warn me again" in the production-mixing dialog.
    /// Persisted: a warning you've dismissed for good should stay dismissed.
    var suppressProductionMixWarning: Bool = false
    /// Modifier for the global K/N chords. Control by default: ⌃K/⌃N collide only with the
    /// emacs-style text bindings most people never use, whereas ⌘N is New File in Xcode.
    /// See NBHotKeyModifier for the full tradeoff.
    var hotKeyModifier: NBHotKeyModifier = .control

    // MARK: Global shortcuts (⌘K / ⌘N — see AppDelegate's global NSEvent monitor)
    /// Bumped whenever the global ⌘K shortcut fires; the search field observes this and
    /// grabs focus. A counter (rather than a bool) so repeated presses always re-trigger it.
    var searchFocusToken: Int = 0

    /// Periodically frees claims older than `autoReleaseMinutes` (the behaviour the
    /// Settings surface advertises). 30s granularity is plenty for a minutes-based limit.
    @ObservationIgnored private var autoReleaseTimer: Timer?

    init() {
        let seed = NBCollection(workspace: MockData.workspace())
        collections = [seed]
        activeCollectionID = seed.id
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
            collections: collections,
            activeCollectionID: activeCollectionID,
            memberID: selfMemberID,
            autoReleaseMinutes: autoReleaseMinutes,
            startExpanded: startExpanded,
            dockEdge: dockEdge,
            onboardingCompleted: onboardingCompleted,
            onboardingName: onboardingName,
            coachMarkPending: pendingCoachMark,
            hotKeyModifier: hotKeyModifier,
            suppressProductionMixWarning: suppressProductionMixWarning
        )
    }

    /// Restores settings + data from a previous session (called once at launch).
    /// Persisted state is user-editable JSON on disk, so it's sanitised here rather than
    /// trusted: `groupOrder`/`groups` are reconciled, and an unusable workspace falls back
    /// to fresh seed data instead of stranding (or crashing) the UI.
    func restore(from persisted: PersistedAppState) {
        selfMemberID = persisted.memberID
        selfName = persisted.onboardingName

        var restored = persisted.collections
        var orphaned = 0
        for index in restored.indices {
            restored[index].workspace.reconcileGroupOrder()
            // A claim by someone absent from `members` can never be released through the UI,
            // so it would lock the row and inflate the notch badge permanently. Heal on load.
            orphaned += restored[index].workspace.releaseOrphanedClaims(ownedBy: [selfMemberID])
        }
        // A collection with no groups at all can't hold or accept anything — same fallback
        // the single-workspace restore had, generalised.
        restored.removeAll { $0.workspace.groups.isEmpty }
        if restored.isEmpty {
            restored = [NBCollection(workspace: MockData.workspace())]
        }

        collections = restored
        activeCollectionID = restored.contains { $0.id == persisted.activeCollectionID }
            ? persisted.activeCollectionID
            : restored[0].id
        if workspace.groups[activeGroupID] == nil {
            activeGroupID = workspace.groupOrder.first ?? ""
        }
        // The Settings stepper enforces this range only for UI-driven changes; the JSON is
        // hand-editable, and an out-of-range value (0, negative) would auto-release every
        // claim within one 30s sweep.
        autoReleaseMinutes = persisted.autoReleaseMinutes.clamped(to: Self.autoReleaseRange)
        startExpanded = persisted.startExpanded
        dockEdge = persisted.dockEdge
        isExpanded = persisted.startExpanded
        pendingCoachMark = persisted.coachMarkPending
        hotKeyModifier = persisted.hotKeyModifier
        suppressProductionMixWarning = persisted.suppressProductionMixWarning

        if orphaned > 0 {
            toast("freed \(orphaned) element\(orphaned == 1 ? "" : "s") used by someone not in this catalogue", color: .amber)
        }
    }

    // MARK: - Derived

    var activeGroup: NBGroup {
        if let group = workspace.groups[activeGroupID] { return group }
        if let firstID = workspace.groupOrder.first, let group = workspace.groups[firstID] { return group }
        // Read on nearly every render — an inconsistent workspace must degrade to an empty
        // group, never trap.
        return NBGroup(id: "", label: "elements", singular: "element", secondaryKey: "", fields: [], elements: [])
    }

    /// The dictionary key `activeGroup` actually resolves to, or nil when the workspace has
    /// no groups at all. Mutating writes must go through this — writing through a stale
    /// `activeGroupID` would mint a phantom group under a bogus key (for example "" after
    /// the last group is deleted), which the group editor then refuses to touch.
    private var resolvedActiveGroupID: String? {
        if workspace.groups[activeGroupID] != nil { return activeGroupID }
        return workspace.groupOrder.first { workspace.groups[$0] != nil }
    }

    /// True when this catalogue has no other members, which is the normal case: Notchboard
    /// works alone and there is no backend to populate a team. Drives hiding the UI that only
    /// makes sense against a teammate's claim.
    var isSolo: Bool { workspace.members.isEmpty }

    var claimedCount: Int {
        workspace.groupOrder.reduce(0) { total, id in
            total + (workspace.groups[id]?.elements.filter(\.isClaimed).count ?? 0)
        }
    }

    var filteredElements: [NBElement] {
        let group = activeGroup
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = group.elements.filter { element in
            let envMatches = environmentFilter == .all || element.environments.contains(environmentFilter)
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

    /// True when this claim belongs to the local user.
    func isMine(_ claim: NBClaim) -> Bool {
        claim.who == selfMemberID
    }

    /// How the local user's claims are labelled: the onboarding first name, lowercase to
    /// match the row typography, with "you" as the fallback while no name is set. This is
    /// the promise the identity step makes ("● ahmed") finally being kept.
    var selfClaimLabel: String {
        let first = selfName.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? "you" : first.lowercased()
    }

    func memberName(_ who: String) -> String {
        if who == selfMemberID { return selfClaimLabel }
        return workspace.members[who]?.name ?? who
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
        // With no groups there is nowhere to put an element — surface why instead of
        // opening a schema-less form whose save would go nowhere.
        guard resolvedActiveGroupID != nil else {
            toast("create a group first", color: .red)
            return
        }
        // Re-invoking while the create form is already open (a repeated ⌘N, the footer
        // button) must not wipe what the user has typed. A fresh form is only set up when
        // coming from anywhere else — including an in-progress edit, whose values must
        // never leak into a new element.
        if currentView == .add && editingElementID == nil { return }
        editingElementID = nil
        addName = ""
        addValues = [:]
        addNote = ""
        addEnvironments = [.dev]
        currentView = .add
    }

    /// Opens the element form prefilled for editing — same form as `openAdd`, save updates
    /// in place instead of creating.
    func openEdit(_ element: NBElement) {
        editingElementID = element.id
        addName = element.name
        // Preserve the element's environments exactly rather than coercing — saveElement
        // writes this back, so a coercion here would silently move any element edited for
        // an unrelated reason. An element with none (hand-edited file) opens as dev so the
        // form is never in an unsaveable state.
        addEnvironments = element.environments.isEmpty ? [.dev] : element.environments
        addNote = element.note
        addValues = element.values
        currentView = .add
    }

    // MARK: - Actions: environment selection

    /// Adds or removes an environment in the add/edit form, refusing to leave the element
    /// with none (an element that belongs nowhere can never be found by the filter).
    func toggleAddEnvironment(_ env: NBEnvironment) {
        guard env != .all else { return }
        if addEnvironments.contains(env) {
            guard addEnvironments.count > 1 else {
                toast("an element needs at least one environment", color: .red)
                return
            }
            addEnvironments.remove(env)
        } else {
            addEnvironments.insert(env)
        }
    }

    /// True when toggling `env` would mix production with another environment and the user
    /// hasn't silenced the warning. The view shows the dialog, then calls
    /// `toggleAddEnvironment` — keeping the decision here and the AppKit modal there makes
    /// this testable without a window.
    func productionMixWarningNeeded(togglingOn env: NBEnvironment) -> Bool {
        guard !suppressProductionMixWarning, env != .all else { return false }
        var candidate = addEnvironments
        if candidate.contains(env) {
            candidate.remove(env)
        } else {
            candidate.insert(env)
        }
        return candidate.contains(.prd) && candidate.count > 1
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
        pendingCoachMark = false // the user found the notch themselves
    }

    // MARK: - Actions: claim tooltip

    func showClaimTooltip(_ elementID: String) {
        tooltipDismissTask?.cancel()
        tooltipElementID = elementID
    }

    /// Dismisses after a short grace period so the cursor can travel from the badge into
    /// the popover. Entering the popover (or re-entering the badge) cancels it.
    func scheduleClaimTooltipDismissal() {
        tooltipDismissTask?.cancel()
        tooltipDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.tooltipElementID = nil
        }
    }

    func cancelClaimTooltipDismissal() {
        tooltipDismissTask?.cancel()
    }

    func dismissClaimTooltip() {
        tooltipDismissTask?.cancel()
        tooltipElementID = nil
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
            if isMine(claim) {
                group.elements[idx].claimedBy = nil
                workspace.groups[activeGroupID] = group
                didFreeElement(group.elements[idx])
                toast("released “\(element.name)”", color: .green)
            } else {
                // Deliberately does not release it — taking someone's element out from under
                // them shouldn't be a single misclick. `takeOver` is the explicit path.
                toast("\(memberName(claim.who)) marked this in use — take it over from the detail view", color: .amber)
            }
        } else {
            group.elements[idx].claimedBy = NBClaim(who: selfMemberID)
            group.elements[idx].lastUsed = "just now, by \(selfClaimLabel)"
            workspace.groups[activeGroupID] = group
            copyPrimaryField(of: element)
        }
    }

    /// Takes an element marked in use by someone else.
    ///
    /// Without a backend there is nobody on the other end to release it, so a foreign claim
    /// is otherwise permanent: `claimOrRelease` refuses it and the auto-release sweep skips
    /// it. That left rows locked forever — the seed data used to ship three of them. A
    /// deliberate, explicitly-labelled takeover is the honest escape hatch, and it is what
    /// the old "ping them or claim anyway" copy promised without ever delivering it.
    func takeOver(_ elementID: String) {
        guard let element = selectedElement(id: elementID), let claim = element.claimedBy, !isMine(claim) else { return }
        let previous = memberName(claim.who)
        mutate(elementID) {
            $0.claimedBy = NBClaim(who: selfMemberID)
            $0.lastUsed = "just now, by \(selfClaimLabel)"
        }
        toast("took “\(element.name)” from \(previous)", color: .amber)
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

    /// Clears a concealed copy off the pasteboard after this window, unless the user has
    /// copied something else since. The concealed-type hint only protects against
    /// cooperating clipboard managers; the plaintext itself would otherwise sit on the
    /// general pasteboard indefinitely.
    private static let concealedPasteboardLifetime: Duration = .seconds(60)
    @ObservationIgnored private var pasteboardClearTask: Task<Void, Never>?

    func copy(_ text: String, label: String, concealed: Bool = false) {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if concealed {
            // Standard hint (nspasteboard.org) telling clipboard managers not to record
            // this entry — used for secret-typed field values.
            pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))

            let changeCount = pasteboard.changeCount
            pasteboardClearTask?.cancel()
            pasteboardClearTask = Task {
                try? await Task.sleep(for: Self.concealedPasteboardLifetime)
                guard !Task.isCancelled else { return }
                let current = NSPasteboard.general
                // Only clear if our copy is still the pasteboard's content — never wipe
                // something the user copied afterwards.
                if current.changeCount == changeCount {
                    current.clearContents()
                }
            }
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

    /// The configured scheme, normalized: strips a pasted "://" and trailing ":" / "/" /
    /// "." / whitespace, so "mythos", "mythos.", "mythos://" and "mythos:" all resolve to
    /// "mythos". A stray trailing dot silently produced an unhandled URL scheme.
    var resolvedDeeplinkScheme: String {
        var scheme = deeplinkScheme.trimmingCharacters(in: .whitespacesAndNewlines)
        if let separator = scheme.range(of: "://") {
            scheme = String(scheme[..<separator.lowerBound])
        }
        return scheme.trimmingCharacters(in: CharacterSet(charactersIn: ":/. "))
    }

    /// Network schemes that would turn the credential deeplink into a web request. A user
    /// pasting their app's universal link ("https://app.example.com") into Settings must
    /// not end up firing username+password as GET parameters at a real host.
    private static let networkSchemes: Set<String> = ["http", "https", "ftp", "file", "ws", "wss"]

    /// True when `scheme` matches the URL-scheme grammar (letter, then letters/digits/
    /// "+"/"-"/".") and is not a network scheme.
    static func isValidDeeplinkScheme(_ scheme: String) -> Bool {
        guard !networkSchemes.contains(scheme.lowercased()) else { return false }
        guard let first = scheme.first, first.isASCII, first.isLetter else { return false }
        return scheme.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "+" || character == "-" || character == ".")
        }
    }

    /// Injection point for tests — fires the deeplink into the simulator. Production uses
    /// the real simctl bridge.
    @ObservationIgnored var deeplinkOpener: (_ url: String, _ completion: @escaping (SimctlBridge.Failure?) -> Void) -> Void = SimctlBridge.openURL

    func loginOnSim(_ element: NBElement) {
        guard let username = loginUsername(for: element) else {
            deeplinkLog.error("login on sim: element “\(element.name, privacy: .public)” has no username field")
            return
        }
        let scheme = resolvedDeeplinkScheme
        guard !scheme.isEmpty else {
            deeplinkLog.error("login on sim: no debug URL scheme configured in settings")
            toast("set your app's debug URL scheme in settings first", color: .red)
            return
        }
        guard Self.isValidDeeplinkScheme(scheme) else {
            deeplinkLog.error("login on sim: “\(scheme, privacy: .public)” is not a usable custom scheme")
            toast("“\(scheme)” isn't a custom URL scheme — set your app's debug scheme in settings", color: .red)
            return
        }
        deeplinkLog.log("login on sim: firing \(scheme, privacy: .public)://debug/login for “\(element.name, privacy: .public)” (password \(self.loginPassword(for: element) != nil ? "included" : "absent", privacy: .public))")
        guard let encodedUser = username.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return }

        var query = "user=\(encodedUser)"
        // Pass the password too when the element has one, so the target app can fill both
        // fields. Username-only apps simply ignore the extra param.
        if let password = loginPassword(for: element),
           let encodedPass = password.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            query += "&pass=\(encodedPass)"
        }

        // Capture the element's owning group AND collection now: the simctl round-trip
        // takes ~0.5-2s, and resolving through the active ids at callback time silently
        // dropped the auto-claim whenever the user switched tabs — or, since Phase 2,
        // collections — mid-flight (while still toasting success).
        guard let owningGroupID = resolvedActiveGroupID else { return }
        let owningCollectionID = activeCollectionID
        let wasFree = element.claimedBy == nil
        deeplinkOpener("\(scheme)://debug/login?\(query)") { [weak self] failure in
            guard let self else { return }
            if let failure {
                // The deeplink never fired — don't leave the element falsely claimed.
                self.toast(failure.userMessage, color: .red)
                return
            }
            // Logging in as this account is de facto using it — auto-claim if it was free
            // (vision §5.3), but only now that the deeplink actually succeeded.
            if wasFree, self.element(element.id, group: owningGroupID, collection: owningCollectionID)?.claimedBy == nil {
                self.mutate(element.id, group: owningGroupID, collection: owningCollectionID) {
                    $0.claimedBy = NBClaim(who: self.selfMemberID)
                    $0.lastUsed = "just now, by \(self.selfClaimLabel)"
                }
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

        switch selectedElement(id: element.id)?.claimedBy {
        case nil:
            mutate(element.id) {
                $0.claimedBy = NBClaim(who: selfMemberID)
                $0.lastUsed = "just now, by \(selfClaimLabel)"
            }
            toast("marked “\(element.name)” in use", color: .green)
        case .some(let claim) where isMine(claim):
            break // already yours; the copy toast is enough
        case .some(let claim):
            toast("\(memberName(claim.who)) has this — coordinate before using", color: .amber)
        }
    }

    /// Internal (not private) so tests can drive the sweep deterministically instead of
    /// waiting on the 30s timer.
    func releaseExpiredClaims() {
        let limit = autoReleaseMinutes
        // Sweeps every collection, not just the visible one — your idle claim in a
        // background collection ages exactly the same way (plan note: "releaseExpiredClaims
        // must sweep all collections").
        for cIndex in collections.indices {
            for groupID in collections[cIndex].workspace.groupOrder {
                guard var group = collections[cIndex].workspace.groups[groupID] else { continue }
                var changed = false
                for idx in group.elements.indices {
                    // Only auto-release your own idle claims — the manual path already
                    // refuses to release someone else's, and other members' claim ages are
                    // simulated/frozen in this local build, so sweeping them would be
                    // meaningless churn.
                    guard let claim = group.elements[idx].claimedBy,
                          isMine(claim), claim.minutesAgo >= limit else { continue }
                    group.elements[idx].claimedBy = nil
                    changed = true
                    didFreeElement(group.elements[idx])
                    toast("auto-released “\(group.elements[idx].name)” after \(limit)m idle", color: .green)
                }
                if changed { collections[cIndex].workspace.groups[groupID] = group }
            }
        }
    }

    private func mutate(_ elementID: String, _ change: (inout NBElement) -> Void) {
        mutate(elementID, in: activeGroupID, change)
    }

    /// Mutates an element inside an explicit group — used by async completions, which must
    /// address the element's *owning* group rather than whatever group is active by the
    /// time they fire.
    private func mutate(_ elementID: String, in groupID: String, _ change: (inout NBElement) -> Void) {
        guard var group = workspace.groups[groupID],
              let idx = group.elements.firstIndex(where: { $0.id == elementID }) else { return }
        change(&group.elements[idx])
        workspace.groups[groupID] = group
    }

    /// Looks an element up in an explicit group (see `mutate(_:in:_:)` for why).
    private func element(_ elementID: String, in groupID: String) -> NBElement? {
        workspace.groups[groupID]?.elements.first { $0.id == elementID }
    }

    /// Fully-addressed variants for async completions: an element's owning *collection*
    /// must be captured at fire time too, or a mid-flight collection switch would land the
    /// mutation in whatever catalogue happens to be active when the callback runs.
    private func mutate(_ elementID: String, group groupID: String, collection collectionID: String, _ change: (inout NBElement) -> Void) {
        guard let cIndex = collections.firstIndex(where: { $0.id == collectionID }),
              var group = collections[cIndex].workspace.groups[groupID],
              let idx = group.elements.firstIndex(where: { $0.id == elementID }) else { return }
        change(&group.elements[idx])
        collections[cIndex].workspace.groups[groupID] = group
    }

    private func element(_ elementID: String, group groupID: String, collection collectionID: String) -> NBElement? {
        collections.first { $0.id == collectionID }?.workspace.groups[groupID]?.elements.first { $0.id == elementID }
    }

    // MARK: - Actions: add/edit element

    func saveElement() {
        let trimmedName = addName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            toast("give it a display name first", color: .red)
            return
        }
        // The placeholder is in-band with user data in state.json: a field literally
        // holding it would be mistaken for a stripped secret on the next load and swap in
        // stale Keychain data (or nothing). Rejecting it at entry is the honest fix.
        guard !addValues.values.contains(AppStateStore.keychainPlaceholder) else {
            toast("that value is reserved by notchboard — pick another", color: .red)
            return
        }
        guard !addEnvironments.isEmpty else {
            toast("pick at least one environment", color: .red)
            return
        }
        // The form's controls make most wrong values hard to type, but values also arrive
        // from imports and hand-edited files — this is the gate that actually holds.
        if let problem = NBFieldValidation.firstProblem(in: addValues, fields: activeGroup.fields) {
            toast(problem, color: .red)
            return
        }

        if let editingID = editingElementID {
            mutate(editingID) { element in
                element.name = trimmedName
                element.environments = addEnvironments
                element.note = addNote.trimmingCharacters(in: .whitespacesAndNewlines)
                element.values = addValues
            }
            editingElementID = nil
            currentView = .detail(elementID: editingID)
            toast("“\(trimmedName)” updated", color: .green)
            return
        }

        // Write through the *resolved* group id: activeGroupID can be stale ("" after the
        // last group was deleted, or a ghost id), and writing activeGroup's fallback
        // contents under that stale key would mint a phantom — or duplicated — group.
        guard let groupID = resolvedActiveGroupID, var group = workspace.groups[groupID] else {
            toast("create a group first", color: .red)
            return
        }
        let element = NBElement(
            id: UUID().uuidString,
            name: trimmedName, environments: addEnvironments, isFavorite: false, claimedBy: nil,
            note: addNote.trimmingCharacters(in: .whitespacesAndNewlines),
            lastUsed: "just now, by \(selfClaimLabel)", values: addValues
        )
        group.elements.append(element)
        workspace.groups[groupID] = group
        currentView = .list
        toast("“\(element.name)” added", color: .green)
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
        let fields = Self.normalisedFields(newGroupFields)
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
        toast("group “\(name)” created", color: .green)
    }

    /// Applies the group form to an existing group. Fields that already existed (matched by
    /// their stable `NBField.id`) keep their `key`, so element values survive a relabel;
    /// only newly added fields derive a key from their label. Values (and Keychain secrets)
    /// of removed fields are dropped.
    private func updateGroup(_ groupID: String, name: String) {
        guard var group = workspace.groups[groupID] else { return }

        let existingByID = Dictionary(uniqueKeysWithValues: group.fields.map { ($0.id, $0) })
        let fields = Self.normalisedFields(newGroupFields, existingByID: existingByID)
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

    // MARK: - Actions: collections

    /// Element ids across every collection *except* the one identified by `excluding` —
    /// the seed for cross-collection dedup at each ingestion point (Keychain account keys
    /// carry no collection component, see NBCollection).
    private func elementIDs(excluding excludedCollectionID: String? = nil) -> Set<String> {
        Set(collections.lazy
            .filter { $0.id != excludedCollectionID }
            .flatMap { $0.workspace.groups.values }
            .flatMap { $0.elements.map(\.id) })
    }

    /// Returns the panel to a coherent state after the catalogue under it changed
    /// wholesale (collection switch/delete, import, seed adoption).
    private func resetTransientUIState() {
        currentView = .list
        searchText = ""
        revealedFieldKeys = []
        keyboardSelectionID = nil
        editingElementID = nil
        editingGroupID = nil
        dismissClaimTooltip()
    }

    func switchCollection(_ id: String) {
        guard id != activeCollectionID, collections.contains(where: { $0.id == id }) else { return }
        activeCollectionID = id
        resetTransientUIState()
        activeGroupID = workspace.groupOrder.first ?? ""
    }

    func createCollection(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            toast("name the collection first", color: .red)
            return
        }
        let collection = NBCollection(workspace: MockData.emptyWorkspace(name: trimmed))
        collections.append(collection)
        switchCollection(collection.id)
        toast("“\(trimmed)” created — \(hotKeyModifier.symbolPrefix)N adds your first element", color: .green)
    }

    /// Sets the active collection's deeplink scheme, validating it the same way
    /// `loginOnSim` does so a bad value is refused where it's typed rather than at the
    /// moment someone needs the feature to work.
    func setDeeplinkScheme(_ raw: String) {
        deeplinkScheme = raw
        let resolved = resolvedDeeplinkScheme
        guard !resolved.isEmpty else {
            // Store the resolved (empty) value, not the raw whitespace the user typed —
            // "  " is not a scheme, and leaving it there makes `isEmpty` checks lie.
            deeplinkScheme = ""
            toast("deeplink scheme cleared — “login on sim” is off for “\(workspace.name)”", color: .amber)
            return
        }
        guard Self.isValidDeeplinkScheme(resolved) else {
            deeplinkScheme = ""
            toast("“\(resolved)” isn't a custom URL scheme — use your app's debug scheme, e.g. notchdemo", color: .red)
            return
        }
        deeplinkScheme = resolved
        toast("“\(workspace.name)” now deeplinks into \(resolved)://", color: .green)
    }

    func renameActiveCollection(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            toast("a collection needs a name", color: .red)
            return
        }
        workspace.name = trimmed
        toast("renamed to “\(trimmed)”", color: .green)
    }

    /// Duplicates the active collection. Every element in the copy gets a fresh id (they
    /// all collide with the source by definition), so the copy's secrets land under their
    /// own Keychain keys on the next save instead of aliasing the original's.
    func duplicateActiveCollection() {
        var seen = elementIDs()
        var copyWorkspace = activeCollection.workspace
        copyWorkspace.name += " copy"
        copyWorkspace.deduplicateElementIDs(seen: &seen)
        let copy = NBCollection(deeplinkScheme: activeCollection.deeplinkScheme, workspace: copyWorkspace)
        collections.append(copy)
        switchCollection(copy.id)
        toast("duplicated as “\(copyWorkspace.name)”", color: .green)
    }

    /// Deletes the active collection and its Keychain secrets. Refuses to delete the last
    /// one — the panel with zero collections is not a state anything else handles.
    func deleteActiveCollection() {
        guard collections.count > 1 else {
            toast("this is the only collection — create another before deleting it", color: .red)
            return
        }
        let doomed = activeCollection
        for key in doomed.workspace.allSecretKeychainKeys {
            SecretsStore.delete(for: key)
        }
        collections.removeAll { $0.id == doomed.id }
        activeCollectionID = collections[0].id
        resetTransientUIState()
        activeGroupID = workspace.groupOrder.first ?? ""
        toast("collection “\(doomed.name)” deleted", color: .red)
    }

    // MARK: - Actions: import/export

    /// Replaces the active collection's catalogue with an imported one (onboarding's
    /// "import a collection file" starting point — the seeded placeholder is what dies).
    /// The trust boundary lives in the import pipeline (WorkspaceTransfer): in-band secret
    /// values are force-blanked there, real ones only enter via the encrypted envelope, and
    /// claims are stripped — so what arrives here is adopted as-is.
    func replaceActiveCollection(with imported: NBWorkspace) {
        adopt(imported)
        toast("imported “\(workspace.name)” · \(workspace.elementCount) elements", color: .green)
    }

    /// Imports as a new collection alongside the existing ones — the menu path. Nothing is
    /// destroyed. Same trust posture as `replaceActiveCollection`.
    func addCollection(_ imported: NBWorkspace, deeplinkScheme: String = "") {
        var clean = imported
        clean.reconcileGroupOrder()
        var seen = elementIDs()
        clean.deduplicateElementIDs(seen: &seen)
        let collection = NBCollection(deeplinkScheme: deeplinkScheme, workspace: clean)
        collections.append(collection)
        activeCollectionID = collection.id
        resetTransientUIState()
        activeGroupID = clean.groupOrder.first ?? ""
        toast("imported “\(clean.name)” · \(clean.elementCount) elements", color: .green)
    }

    /// Adopts a freshly-seeded catalogue (onboarding's "sample" and "empty" starting
    /// points). Shares `adopt` with the import-replace path so the reset behaviour can't
    /// drift.
    func adoptSeedWorkspace(_ seeded: NBWorkspace) {
        adopt(seeded)
    }

    /// Replaces every collection from a decrypted snapshot — the §14.5.2 recovery path.
    /// Whole-app-wide on purpose: a snapshot is a consistent moment in time, and restoring
    /// half of one would manufacture exactly the inconsistency it exists to undo.
    func restoreCollections(_ incoming: [NBCollection], activeID: String) {
        guard !incoming.isEmpty else {
            toast("that snapshot is empty — nothing restored", color: .red)
            return
        }
        for key in collections.allSecretKeychainKeys {
            SecretsStore.delete(for: key)
        }
        var restored = incoming
        for index in restored.indices {
            restored[index].workspace.reconcileGroupOrder()
        }
        restored.deduplicateElementIDsAcrossCollections()
        collections = restored
        activeCollectionID = restored.contains { $0.id == activeID } ? activeID : restored[0].id
        resetTransientUIState()
        activeGroupID = workspace.groupOrder.first ?? ""
        watchedElementIDs = []
        toast("restored \(restored.count) collection\(restored.count == 1 ? "" : "s") from snapshot", color: .green)
    }

    /// Swaps the active collection's catalogue and returns the UI to a coherent state.
    /// Purges the outgoing catalogue's Keychain entries — nothing else references them
    /// once it's gone.
    private func adopt(_ incoming: NBWorkspace) {
        for key in workspace.allSecretKeychainKeys {
            SecretsStore.delete(for: key)
        }

        var clean = incoming
        clean.reconcileGroupOrder()
        // Duplicate element IDs — within the incoming file or against the *other*
        // collections — would collide in the Keychain and make row actions hit the wrong
        // element. Remap before adopting.
        var seen = elementIDs(excluding: activeCollectionID)
        clean.deduplicateElementIDs(seen: &seen)
        workspace = clean
        activeGroupID = clean.groupOrder.first ?? ""
        resetTransientUIState()
        // Watches on the discarded catalogue's elements can never fire — drop only those.
        let remaining = elementIDs()
        watchedElementIDs = watchedElementIDs.intersection(remaining)
    }

    /// Drops empty-labelled fields, derives keys (preserving the stable key of any field
    /// that already existed, matched by `NBField.id`), and dedupes colliding keys with a
    /// trailing underscore. Shared by the create and edit paths — they previously diverged,
    /// and the create path let "user id" and "user-id" silently share one values slot.
    static func normalisedFields(_ raw: [NBField], existingByID: [UUID: NBField] = [:]) -> [NBField] {
        var usedKeys = Set<String>()
        var fields: [NBField] = []
        for field in raw where !field.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var f = field
            f.key = existingByID[field.id]?.key ?? Self.slug(field.label)
            while usedKeys.contains(f.key) { f.key += "_" }
            usedKeys.insert(f.key)
            fields.append(f)
        }
        return fields
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

    /// Resets panel state when onboarding is replayed (the flow itself is owned by
    /// OnboardingViewModel.reset(); both are invoked together from the menu/Settings).
    func replayOnboarding() {
        currentView = .list
        showCoachMark = false
        pendingCoachMark = false
    }
}

struct NBToast: Identifiable, Equatable {
    let id: UUID
    let message: String
    let color: NBToastColor
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
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
