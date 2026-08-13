//
//  NotchboardViewModel.swift
//  notchboard
//
//  The panel's coordinator: chrome, navigation, filters, settings, and the actions that
//  need more than one collaborator (claiming, the deeplink bridge, import/export).
//
//  What it deliberately does NOT own any more, after the 2026-08-07 decomposition:
//
//  - `CollectionStore`  — the catalogues, element addressing, collection lifecycle
//  - `ElementFormModel` / `GroupFormModel` — what the user has typed into the two forms
//  - `ToastCenter`      — the message stack
//  - `Clipboard`        — pasteboard writes and the concealed-copy expiry
//  - `NBDeeplinkScheme` — scheme normalisation, validation, URL building
//
//  The line is drawn at UX: those types hold state and rules, this one decides what the
//  user sees happen. `workspace`, `collections` and friends stay here as facades so the
//  read-modify-write call sites throughout keep reading the way they always have.
//

import Foundation
import Observation
import SwiftUI
import os

private let deeplinkLog = Logger(subsystem: "flourix.notchboard", category: "deeplink")

enum NotchboardPanelView: Equatable {
    case list
    case detail(elementID: String)
    case add
    case newGroup
}

@Observable
final class NotchboardViewModel {
    // MARK: Collaborators
    let store = CollectionStore()
    let elementForm = ElementFormModel()
    let groupForm = GroupFormModel()
    let toastCenter = ToastCenter()
    @ObservationIgnored private let clipboard = Clipboard()

    // MARK: Chrome
    var isExpanded: Bool = true
    var showCoachMark: Bool = false
    /// Set when onboarding finishes while Simulator isn't running: the coach mark is
    /// deferred until Simulator first appears instead of being silently skipped — the
    /// unexplained 28pt notch was the only thing a Simulator-less onboarder ever saw.
    var pendingCoachMark: Bool = false
    /// The menu-bar fallback (vision.md §9): show the panel undocked instead of hiding it
    /// when there is no Simulator window to dock against. AppDelegate reads this on its
    /// reposition tick.
    ///
    /// Lives here rather than in AppDelegate because two places set it — the menu item and
    /// the end of onboarding, which needs somewhere to land a user whose Mac cannot dock.
    var fallbackPanelVisible: Bool = false

    // MARK: Identity (vision.md §14.2 — the standing prerequisite for any future sync)
    /// Stable local member id: what this user's claims are attributed to.
    var selfMemberID: String = UUID().uuidString
    /// The onboarding display name. Labels this user's claims; empty falls back to "you".
    /// Settable only through `updateSelfName` (and `restore`), because a bare assignment
    /// moves the panel's copy and leaves the room publishing the old one.
    private(set) var selfName: String = ""
    /// Debounces the room push in `updateSelfName`.
    @ObservationIgnored private var pendingSelfNamePush: Task<Void, Never>?
    private static let selfNamePushDebounce: Duration = .milliseconds(500)

    // MARK: Sync (vision.md §14.2)
    /// The room coordinator, when the app runs for real. Weak: AppDelegate owns it, and
    /// nil (every test, and any run before wiring) simply means no rooms. All room copy
    /// lives HERE, not in the engine — including the "in use", never "claim" rule.
    @ObservationIgnored weak var syncEngine: SyncEngine?

    /// The active collection's room session, for the header dot and presence count.
    var activeRoomSession: RoomSession? {
        syncEngine?.session(for: activeCollectionID)
    }

    /// What the connection dot shows: nil = no room configured (amber, as always);
    /// a configured room with no session yet reads as disconnected rather than "no room".
    var activeRoomState: SyncConnectionState? {
        guard activeCollection.room != nil else { return nil }
        return activeRoomSession?.state ?? .disconnected
    }

    /// " · offline" when a mark's holder isn't in the room right now — appended to the
    /// status line, the use button, and the row tooltip so all three tell the same story.
    func presenceSuffix(for claim: NBClaim) -> String {
        guard !isMine(claim), let session = activeRoomSession, session.state == .connected else { return "" }
        return session.isEffectivelyFree(claim) ? " · offline" : ""
    }

    /// Sets up (or re-points) the active collection's room from the ▾ menu. The one flow
    /// where broker details get typed — the engine seals the account password into the
    /// config, and from then on "copy room invite" carries everything a joiner needs
    /// except the room password.
    func setUpRoomFromMenu() {
        guard let engine = syncEngine else {
            toast("rooms aren't available in this build", color: .red)
            return
        }
        guard var setup = RoomDialogs.promptForRoomSetup(
            collectionName: workspace.name, current: activeCollection.room
        ) else { return }
        // Re-pointing the same room with the account fields left blank keeps the sealed
        // credential — retyping it on every settings visit would be the old three-password
        // dance again. If the room password ALSO changed, the old seal won't open under
        // the new key and the wrongPassword event says to re-run setup.
        //
        // The username has to match too, not just host and room: carrying an old account's
        // sealed password forward under a newly typed username pairs two halves of two
        // different credentials, and every connection then fails auth for no visible reason.
        if setup.brokerPassword == nil, let current = activeCollection.room,
           current.brokerHost == setup.config.brokerHost, current.room == setup.config.room,
           URL(string: current.brokerURL)?.user(percentEncoded: false)
               == URL(string: setup.config.brokerURL)?.user(percentEncoded: false) {
            var config = setup.config
            config.sealedBrokerPassword = current.sealedBrokerPassword
            setup = RoomDialogs.RoomSetup(config: config, roomPassword: setup.roomPassword, brokerPassword: nil)
        }
        guard RoomKeyStore.saveRoomPassword(setup.roomPassword, for: setup.config) else {
            // The SecretsStore rule: a failed Keychain write is NOT stored — joining
            // anyway would work until the next relaunch, then silently stop.
            toast("couldn't store the room password in the Keychain — not joining", color: .red)
            return
        }
        engine.joinRoom(setup.config, password: setup.roomPassword, collectionID: activeCollectionID,
                        brokerPassword: setup.brokerPassword)
        toast("joining “\(setup.config.room)” — copy the invite from the ▾ menu once it's green", color: .amber)
    }

    /// Puts the one-line invite on the pasteboard. Everything a joiner needs except the
    /// room password: address, room, and the broker credential sealed under the room key.
    func copyRoomInvite() {
        // No "is it sealed yet?" guard here. A username with no password is a legitimate
        // broker setup, and gating on the URL carrying a username refused those invites
        // forever while telling the user to try again shortly. The race it was aimed at
        // barely exists either: the collection only gains a room config in `startSession`,
        // which is the same place the seal is written, so a config that exists is a config
        // whose seal is already whatever it will be.
        guard let room = activeCollection.room else { return }
        guard let invite = RoomInvite.encode(room) else {
            toast("couldn't build the invite", color: .red)
            return
        }
        clipboard.copy(invite, concealed: false)
        toast("invite copied — share it with the room password, separately", color: .green)
    }

    /// The invitee's front door, from the ▾ menu: paste the invite, type the room
    /// password, adopt the room's catalogue.
    func joinWithInviteFromMenu() {
        guard syncEngine != nil else {
            toast("rooms aren't available in this build", color: .red)
            return
        }
        guard let answer = RoomDialogs.promptToJoinWithInvite(memberName: selfClaimLabel) else { return }
        joinRoomWithPassword(answer.config, roomPassword: answer.roomPassword, collectionID: activeCollectionID)
    }

    /// The single join gateway for every invitee-shaped path (invite paste, imported
    /// file, onboarding): store the password, pin the config, hand off to the engine.
    /// Returns false when the Keychain refused the write (the caller's flow must stop —
    /// the SecretsStore rule).
    @discardableResult
    func joinRoomWithPassword(_ config: NBRoomConfig, roomPassword: String, collectionID: String) -> Bool {
        guard let engine = syncEngine else { return false }
        var incoming = config
        incoming.firstSyncCompleted = false // a joiner has never merged, whatever travelled
        guard RoomKeyStore.saveRoomPassword(roomPassword, for: incoming) else {
            toast("couldn't store the room password in the Keychain — not joining", color: .red)
            return false
        }
        store.setRoomConfig(incoming, collectionID: collectionID)
        engine.joinRoom(incoming, password: roomPassword, collectionID: collectionID)
        toast("joining “\(incoming.room)”…", color: .amber)
        return true
    }

    func leaveRoomFromMenu() {
        guard let room = activeCollection.room else { return }
        guard RoomDialogs.confirmLeave(roomName: room.room, collectionName: workspace.name) else { return }
        syncEngine?.leaveRoom(collectionID: activeCollectionID)
        RoomKeyStore.deletePasswords(for: room)
        store.setRoomConfig(nil, collectionID: activeCollectionID)
        toast("left “\(room.room)” — “\(workspace.name)” is local again", color: .amber)
    }

    /// §14.3's join moment: an imported file carried a room address. "Not now" keeps the
    /// address on the collection so the ▾ menu can join later.
    func offerToJoinImportedRoom(_ room: NBRoomConfig, collectionID: String) {
        var incoming = room
        incoming.firstSyncCompleted = false // an importer has never merged, whatever the file says
        store.setRoomConfig(incoming, collectionID: collectionID)
        guard syncEngine != nil else { return }
        guard let roomPassword = RoomDialogs.promptToJoinImportedRoom(room: incoming, memberName: selfClaimLabel) else {
            toast("staying local — join “\(incoming.room)” any time from the ▾ menu", color: .amber)
            return
        }
        joinRoomWithPassword(incoming, roomPassword: roomPassword, collectionID: collectionID)
    }

    /// Whether an element is *actually* blocked: a mark held by someone offline renders
    /// free (§14.2's live twin of releaseOrphanedClaims) — strictly a rendering rule, the
    /// mark itself survives their reconnect.
    func isEffectivelyFree(_ element: NBElement) -> Bool {
        guard let claim = element.claimedBy else { return true }
        guard !isMine(claim) else { return false }
        return syncEngine?.session(for: activeCollectionID)?.isEffectivelyFree(claim) ?? false
    }

    func handleRoomEvent(collectionID: String, event: RoomEvent) {
        let name = collections.first { $0.id == collectionID }?.name ?? "collection"
        switch event {
        case .connected(let onlineCount):
            toast("“\(name)” room connected · \(onlineCount) online", color: .green)
        case .wrongPassword:
            toast("wrong room password for “\(name)” — or it changed; ask for a fresh invite", color: .red)
        case .failed(let message):
            toast("“\(name)”: \(message) — changes staying local until it's back", color: .red)
        case .adoptedRoomState(let elementCount):
            toast("joined “\(name)” · \(elementCount) elements from the room (local copy snapshotted)", color: .green)
        case .elementFreed(let element):
            handleElementFreed(element)
        }
    }

    // MARK: Navigation / filters
    /// The group the list is showing.
    ///
    /// Reads self-heal. The stored id can go stale without anyone touching it — a teammate
    /// deletes the group and the tombstone arrives, or a first-connect adopt replaces the
    /// whole catalogue — and `activeGroup` has always fallen back to the first surviving
    /// group so the panel keeps rendering. The mutations did not: they addressed the raw
    /// stored id, so the store's `guard let group = …` dropped them on the floor and the
    /// user's click did nothing, silently. Resolving on read is what keeps "the group you
    /// are looking at" and "the group you are writing to" from ever disagreeing again.
    var activeGroupID: String {
        get {
            if workspace.groups[storedActiveGroupID] != nil { return storedActiveGroupID }
            return workspace.groupOrder.first { workspace.groups[$0] != nil } ?? storedActiveGroupID
        }
        set { storedActiveGroupID = newValue }
    }

    private var storedActiveGroupID: String = "users"
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

    // MARK: Settings (mirrors the prototype's configurable props)
    /// Allowed auto-release window — the single definition shared by the Settings stepper
    /// and the restore-time clamp.
    static let autoReleaseRange = 5...240
    var autoReleaseMinutes: Int = 60
    var startExpanded: Bool = true
    /// Which edge of the Simulator window the notch/panel docks to.
    var dockEdge: NBDockEdge = .right
    /// Set once the user ticks "don't warn me again" in the production-mixing dialog.
    /// Persisted: a warning you've dismissed for good should stay dismissed.
    var suppressProductionMixWarning: Bool = false
    /// Whether notify-when-free notifications play a sound. On by default — the point of
    /// watching an element is to be interrupted — with the off switch in Settings.
    var notificationSoundEnabled: Bool = true
    /// Modifier for the global K/N chords. Control by default: ⌃K/⌃N collide only with the
    /// emacs-style text bindings most people never use, whereas ⌘N is New File in Xcode.
    /// See NBHotKeyModifier for the full tradeoff.
    var hotKeyModifier: NBHotKeyModifier = .control

    // MARK: Global shortcuts (see AppDelegate's Carbon registration)
    /// Bumped whenever the global search shortcut fires; the search field observes this and
    /// grabs focus. A counter (rather than a bool) so repeated presses always re-trigger it.
    var searchFocusToken: Int = 0

    /// Periodically frees claims older than `autoReleaseMinutes` (the behaviour the
    /// Settings surface advertises). 30s granularity is plenty for a minutes-based limit.
    @ObservationIgnored private var autoReleaseTimer: Timer?

    init() {
        // The store stamps content edits with the editor's identity (NBElement.updatedBy);
        // it needs to know who that is from the first mutation, not from the first restore.
        store.selfMemberID = selfMemberID
        autoReleaseTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.releaseExpiredClaims()
        }
    }

    deinit {
        autoReleaseTimer?.invalidate()
    }

    // MARK: - Facades over the store
    //
    // Kept on the view model because they are how the whole app refers to its data; the
    // logic behind them lives in CollectionStore.

    var collections: [NBCollection] {
        get { store.collections }
        set { store.collections = newValue }
    }

    var activeCollectionID: String {
        get { store.activeCollectionID }
        set { store.activeCollectionID = newValue }
    }

    var activeCollection: NBCollection { store.active }

    var workspace: NBWorkspace {
        get { store.workspace }
        set { store.workspace = newValue }
    }

    /// The target app's debug URL scheme for "login on sim". Per collection: switching
    /// collections switches the app you deeplink into. Empty means the bridge is
    /// unconfigured for this collection.
    var deeplinkScheme: String {
        get { store.deeplinkScheme }
        set { store.deeplinkScheme = newValue }
    }

    var toasts: [NBToast] { toastCenter.items }

    // MARK: - Persistence

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
            suppressProductionMixWarning: suppressProductionMixWarning,
            notificationSoundEnabled: notificationSoundEnabled
        )
    }

    /// Restores settings + data from a previous session (called once at launch). Persisted
    /// state is user-editable JSON on disk, so the store sanitises it rather than trusting
    /// it.
    func restore(from persisted: PersistedAppState) {
        selfMemberID = persisted.memberID
        selfName = persisted.onboardingName
        store.selfMemberID = persisted.memberID

        let orphaned = store.adoptPersisted(
            persisted.collections,
            activeID: persisted.activeCollectionID,
            selfMemberID: selfMemberID
        )

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
        notificationSoundEnabled = persisted.notificationSoundEnabled

        if orphaned > 0 {
            toast("freed \(orphaned) element\(orphaned == 1 ? "" : "s") used by someone not in this catalogue", color: .amber)
        }
    }

    // MARK: - Derived

    var activeGroup: NBGroup {
        if let group = workspace.groups[activeGroupID] { return group }
        // Read on nearly every render — an inconsistent workspace must degrade to an empty
        // group, never trap. Reached only when the catalogue has no groups at all, since
        // `activeGroupID` resolves to a surviving group whenever one exists.
        return NBGroup(id: "", label: "elements", singular: "element", secondaryKey: "", fields: [], elements: [])
    }

    /// The dictionary key `activeGroup` actually resolves to, or nil when the workspace has
    /// no groups at all. Creating writes go through this so they can't mint a phantom group
    /// under a bogus key (for example "" after the last group is deleted), which the group
    /// editor would then refuse to touch.
    private var resolvedActiveGroupID: String? {
        workspace.groups[activeGroupID] != nil ? activeGroupID : nil
    }

    /// True when this catalogue has no other members, which is the normal case: Notchboard
    /// works alone and there is no backend to populate a team. Drives hiding the UI that
    /// only makes sense against someone else's in-use mark.
    var isSolo: Bool { workspace.members.isEmpty }

    var claimedCount: Int {
        workspace.groupOrder.reduce(0) { total, id in
            total + (workspace.groups[id]?.elements.filter(\.isClaimed).count ?? 0)
        }
    }

    /// People in the active collection's room right now, including you; nil when there is
    /// no live room (the footer shows nothing rather than a fake count).
    var onlineCount: Int? {
        guard let session = activeRoomSession, session.state == .connected else { return nil }
        return session.onlineMemberIDs.count + 1
    }

    var filteredElements: [NBElement] {
        let group = activeGroup
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Secret-typed values are deliberately out of the haystack (decided 2026-08-13,
        // vision.md §13.16). Two reasons, and the first is a plain defect: row subtitles mask
        // secrets, so a match on one produced a row with nothing on screen containing what
        // was typed. The second is that a search field which confirms substrings of a
        // password is a guessing oracle, on a panel that sits open next to a Simulator
        // somebody else is watching.
        //
        // Keyed off the schema rather than off `values`, so a value whose field was deleted
        // (type unknowable now) stays out too — it isn't rendered anywhere either.
        let searchableKeys = group.fields.filter { $0.type != .secret }.map(\.key)
        let filtered = group.elements.filter { element in
            let envMatches = environmentFilter == .all || element.environments.contains(environmentFilter)
            guard envMatches else { return false }
            guard !query.isEmpty else { return true }
            let haystack = ([element.name, element.note] + searchableKeys.compactMap { element.values[$0] })
                .joined(separator: " ")
                .lowercased()
            return haystack.contains(query)
        }
        return filtered.sorted { ($0.isFavorite ? 1 : 0) > ($1.isFavorite ? 1 : 0) }
    }

    func secondaryText(for element: NBElement, in group: NBGroup) -> String {
        // Every read goes through `displayValue`, on every branch: a row has no reveal
        // toggle, so a secret-typed field can only ever render as bullets here — including
        // through the special cases below, which name their fields directly and would
        // otherwise be a second way past the mask.
        //
        // Special-cased formats only apply when the schema actually carries those fields —
        // group IDs alone aren't a contract once users create their own groups.
        if group.id == "promos", let pct = group.displayValue("discount_pct", of: element) {
            return "\(pct)% off · exp \(group.displayValue("expires", of: element) ?? "—")"
        }
        if group.id == "products", let sku = group.displayValue("sku", of: element) {
            return "\(sku) · €\(group.displayValue("price", of: element) ?? "")"
        }
        return group.displayValue(group.secondaryKey, of: element) ?? ""
    }

    /// True when this claim belongs to the local user.
    func isMine(_ claim: NBClaim) -> Bool {
        claim.who == selfMemberID
    }

    /// The one way the display name changes. Two copies have to move: this one, which the
    /// panel renders, and the engine's, which every claim and presence publish carries —
    /// writing `selfName` alone left teammates on the launch-time name until relaunch.
    ///
    /// The room half is debounced exactly like AppStateStore's save, and for the same
    /// reason: the name field is bound per keystroke, and one presence publish per
    /// character would have the room watch a name being typed.
    func updateSelfName(_ name: String) {
        guard name != selfName else { return }
        selfName = name
        pendingSelfNamePush?.cancel()
        pendingSelfNamePush = Task { [weak self] in
            try? await Task.sleep(for: Self.selfNamePushDebounce)
            guard !Task.isCancelled, let self else { return }
            syncEngine?.updateSelfName(selfName)
        }
    }

    /// How the local user's marks are labelled: the onboarding first name, lowercase to
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
        if currentView == .add && !elementForm.isEditing { return }
        elementForm.reset()
        currentView = .add
    }

    /// Opens the element form prefilled for editing — same form as `openAdd`, save updates
    /// in place instead of creating.
    func openEdit(_ element: NBElement) {
        elementForm.prefill(from: element)
        currentView = .add
    }

    /// Adds or removes an environment in the element form, explaining the one refusal.
    /// Toggling is always one click — the production-mixing warning fires once, on save,
    /// not on every chip (first team test: per-toggle prompts read as spam).
    func toggleAddEnvironment(_ env: NBEnvironment) {
        if !elementForm.toggleEnvironment(env), elementForm.environments.contains(env) {
            toast("an element needs at least one environment", color: .red)
        }
    }

    func openNewGroup() {
        groupForm.reset()
        currentView = .newGroup
    }

    /// Opens the group form prefilled with the active group's name and schema.
    func openEditGroup() {
        let group = activeGroup
        guard !group.id.isEmpty else { return }
        groupForm.prefill(from: group)
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
        // Local-only on purpose: a favourite is personal, it never travels, and it must
        // never bump the content timestamp (or starring a row would beat a teammate's
        // real edit in conflict resolution).
        store.mutateLocalOnly(elementID, in: activeGroupID) { $0.isFavorite.toggle() }
    }

    func claimOrRelease(_ elementID: String) {
        guard let element = workspace.groups[activeGroupID]?
            .elements.first(where: { $0.id == elementID }) else { return }

        if let claim = element.claimedBy {
            if isMine(claim) {
                store.setClaim(nil, elementID: elementID, group: activeGroupID, collection: activeCollectionID)
                handleElementFreed(element)
                toast("released “\(element.name)”", color: .green)
            } else if isEffectivelyFree(element) {
                // The holder is offline, so the row renders free (§14.2) — using it is a
                // legitimate, user-initiated takeover, not a presence-flicker mutation.
                store.setClaim(NBClaim(who: selfMemberID), elementID: elementID,
                               group: activeGroupID, collection: activeCollectionID,
                               claimantName: selfClaimLabel)
                store.mutate(elementID, in: activeGroupID) { $0.lastUsed = "just now, by \(selfClaimLabel)" }
                toast("took “\(element.name)” — \(memberName(claim.who)) is offline", color: .amber)
                copyPrimaryField(of: element)
            } else {
                // Deliberately does not release it — taking someone's element out from
                // under them shouldn't be a single misclick. `takeOver` is the explicit
                // path.
                toast("\(memberName(claim.who)) marked this in use — take it over from the detail view", color: .amber)
            }
        } else {
            store.setClaim(NBClaim(who: selfMemberID), elementID: elementID,
                           group: activeGroupID, collection: activeCollectionID,
                           claimantName: selfClaimLabel)
            // The mark and the visible trace are two different changes on the wire: the
            // claim has its own topic and timestamp, lastUsed is content and bumps.
            store.mutate(elementID, in: activeGroupID) { $0.lastUsed = "just now, by \(selfClaimLabel)" }
            copyPrimaryField(of: element)
        }
    }

    /// Takes an element marked in use by someone else.
    ///
    /// Without a backend there is nobody on the other end to release it, so someone else's
    /// mark is otherwise permanent: `claimOrRelease` refuses it and the auto-release sweep
    /// skips it. That left rows locked forever — the seed data used to ship three of them.
    /// A deliberate, explicitly-labelled takeover is the honest escape hatch.
    func takeOver(_ elementID: String) {
        guard let element = selectedElement(id: elementID), let claim = element.claimedBy, !isMine(claim) else { return }
        let previous = memberName(claim.who)
        store.setClaim(NBClaim(who: selfMemberID), elementID: elementID,
                       group: activeGroupID, collection: activeCollectionID,
                       claimantName: selfClaimLabel)
        store.mutate(elementID, in: activeGroupID) { $0.lastUsed = "just now, by \(selfClaimLabel)" }
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

    /// Arms a watch — but only once the system will actually let us deliver it. The panel
    /// is usually collapsed to a 36pt notch when the news arrives, so a macOS notification
    /// is the whole feature, not a garnish on a toast: with permission refused there is
    /// nothing to arm, and the action aborts loudly instead of pretending.
    func notifyWhenFree(_ element: NBElement) {
        Task { [weak self] in
            let permission = await Notifier.authorize()
            guard let self else { return }
            switch permission {
            case .granted, .unavailable:
                self.watchedElementIDs.insert(element.id)
                self.toast("you'll be notified when “\(element.name)” is free", color: .green)
            case .denied:
                self.toast("notifications are off for notchboard — turn them on in System Settings", color: .red)
                Notifier.openSystemSettings()
            }
        }
    }

    /// Called whenever an element's mark is cleared — manual release, auto-release, a
    /// remote release, or the holder going offline. If it was being watched, fire a local
    /// notification and drop the watch. Internal because room events route through it.
    func handleElementFreed(_ element: NBElement) {
        guard watchedElementIDs.remove(element.id) != nil else { return }
        Notifier.notifyElementFree(name: element.name, withSound: notificationSoundEnabled)
        toast("“\(element.name)” is now free", color: .green)
    }

    func copy(_ text: String, label: String, concealed: Bool = false) {
        clipboard.copy(text, concealed: concealed)
        toast("\(label) copied to clipboard", color: .amber)
    }

    /// Copies an element's primary (first schema) field — the row copy button and the
    /// copy-and-mark flow share this so the "what is primary" logic lives in one place.
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

    /// The configured scheme, normalised (see NBDeeplinkScheme).
    var resolvedDeeplinkScheme: String {
        NBDeeplinkScheme.resolve(deeplinkScheme)
    }

    /// Sets the active collection's deeplink scheme, validating it the same way
    /// `loginOnSim` does so a bad value is refused where it's typed rather than at the
    /// moment someone needs the feature to work.
    func setDeeplinkScheme(_ raw: String) {
        let resolved = NBDeeplinkScheme.resolve(raw)
        guard !resolved.isEmpty else {
            // Store the resolved (empty) value, not the raw whitespace the user typed —
            // "  " is not a scheme, and leaving it there makes `isEmpty` checks lie.
            deeplinkScheme = ""
            toast("deeplink scheme cleared — “login on sim” is off for “\(workspace.name)”", color: .amber)
            return
        }
        guard NBDeeplinkScheme.isValid(resolved) else {
            deeplinkScheme = ""
            toast("“\(resolved)” isn't a custom URL scheme — use your app's debug scheme, e.g. notchdemo", color: .red)
            return
        }
        deeplinkScheme = resolved
        toast("“\(workspace.name)” now deeplinks into \(resolved)://", color: .green)
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
            deeplinkLog.error("login on sim: no debug URL scheme configured for this collection")
            toast("set this collection's debug URL scheme first — the ▾ menu by its name", color: .red)
            return
        }
        guard NBDeeplinkScheme.isValid(scheme) else {
            deeplinkLog.error("login on sim: “\(scheme, privacy: .public)” is not a usable custom scheme")
            toast("“\(scheme)” isn't a custom URL scheme — set your app's debug scheme", color: .red)
            return
        }
        let password = loginPassword(for: element)
        deeplinkLog.log("login on sim: firing \(scheme, privacy: .public)://debug/login for “\(element.name, privacy: .public)” (password \(password != nil ? "included" : "absent", privacy: .public))")
        guard let url = NBDeeplinkScheme.debugLoginURL(scheme: scheme, username: username, password: password) else { return }

        // Capture the element's owning group AND collection now: the simctl round-trip
        // takes ~0.5-2s, and resolving through the active ids at callback time silently
        // dropped the auto-mark whenever the user switched tabs — or collections —
        // mid-flight (while still toasting success).
        guard let owningGroupID = resolvedActiveGroupID else { return }
        let owningCollectionID = activeCollectionID
        let wasFree = element.claimedBy == nil
        deeplinkOpener(url) { [weak self] failure in
            guard let self else { return }
            if let failure {
                // The deeplink never fired — don't leave the element falsely marked.
                self.toast(failure.userMessage, color: .red)
                return
            }
            // Logging in as this account is de facto using it — auto-mark if it was free
            // (vision §5.3), but only now that the deeplink actually succeeded.
            if wasFree, self.store.element(element.id, group: owningGroupID, collection: owningCollectionID)?.claimedBy == nil {
                self.store.setClaim(NBClaim(who: self.selfMemberID), elementID: element.id,
                                    group: owningGroupID, collection: owningCollectionID,
                                    claimantName: self.selfClaimLabel)
                self.store.mutate(element.id, group: owningGroupID, collection: owningCollectionID) {
                    $0.lastUsed = "just now, by \(self.selfClaimLabel)"
                }
            }
            self.toast("⚡ logged in as “\(element.name)” on simulator", color: .green)
        }
    }

    /// Copies an auth element's login and password to the clipboard (concealed) and marks
    /// the element in use. This is the fallback for logins the deeplink can't drive —
    /// WebView/SSO screens (Okta and the like) — where the user pastes the credentials by
    /// hand but still wants the element marked so teammates don't collide.
    /// Copies just the password, concealed, with no effect on the mark.
    ///
    /// This replaced a second "copy login + password · mark in use" button that sat next to
    /// "use + copy" and read as its twin (team feedback: "they seem like the same thing").
    /// They weren't — one copied the username, the other copied both joined by a newline —
    /// but a two-line clipboard is the wrong shape for a login form anyway. Two buttons
    /// that copy one field each, in the order you paste them, is the honest split.
    func copyPassword(of element: NBElement) {
        guard let password = loginPassword(for: element) else { return }
        copy(password, label: "password", concealed: true)
    }

    /// Internal (not private) so tests can drive the sweep deterministically instead of
    /// waiting on the 30s timer.
    func releaseExpiredClaims() {
        let limit = autoReleaseMinutes
        // Sweeps every collection, not just the visible one — your idle mark in a
        // background collection ages exactly the same way. Iterates a value copy while
        // releasing through the store, so the walk can't trip over its own mutations.
        for collection in collections {
            for groupID in collection.workspace.groupOrder {
                guard let group = collection.workspace.groups[groupID] else { continue }
                for element in group.elements {
                    // Only auto-release your own idle marks — the manual path already
                    // refuses to release someone else's, and other members' ages are
                    // frozen until their Mac speaks, so sweeping them would be
                    // meaningless churn.
                    guard let claim = element.claimedBy,
                          isMine(claim), claim.minutesAgo >= limit else { continue }
                    store.setClaim(nil, elementID: element.id, group: groupID, collection: collection.id)
                    handleElementFreed(element)
                    toast("auto-released “\(element.name)” after \(limit)m idle", color: .green)
                }
            }
        }
    }

    // MARK: - Actions: add/edit element

    /// Test seam for the production-mixing dialog (the deeplinkOpener pattern) — a modal
    /// in `saveElement` would hang the suite.
    @ObservationIgnored var confirmProductionMix: (_ elementName: String) -> EnvironmentWarningDialog.Answer
        = EnvironmentWarningDialog.confirmProductionMix

    func saveElement() {
        let (trimmedName, trimmedNote, problem) = elementForm.validated(against: activeGroup.fields)
        if let problem {
            toast(problem, color: .red)
            return
        }

        // The production-mixing speed bump, once, at the moment of commitment — not on
        // every environment chip (first team test: per-toggle prompts read as spam, and
        // half of them interrupted combinations the user was about to change anyway).
        if elementForm.environments.mixesProductionWithOthers, !suppressProductionMixWarning {
            let answer = confirmProductionMix(trimmedName)
            if answer.suppressFuture { suppressProductionMixWarning = true }
            guard answer.confirmed else { return } // stay on the form, nothing saved
        }

        if let editingID = elementForm.editingElementID {
            store.mutate(editingID, in: activeGroupID) { element in
                element.name = trimmedName
                element.environments = self.elementForm.environments
                element.note = trimmedNote
                element.values = self.elementForm.values
            }
            elementForm.editingElementID = nil
            currentView = .detail(elementID: editingID)
            toast("“\(trimmedName)” updated", color: .green)
            return
        }

        // Write through the *resolved* group id: activeGroupID can be stale ("" after the
        // last group was deleted, or a ghost id), and writing activeGroup's fallback
        // contents under that stale key would mint a phantom — or duplicated — group.
        guard let groupID = resolvedActiveGroupID else {
            toast("create a group first", color: .red)
            return
        }
        let element = NBElement(
            id: UUID().uuidString,
            name: trimmedName, environments: elementForm.environments, isFavorite: false, claimedBy: nil,
            note: trimmedNote,
            lastUsed: "just now, by \(selfClaimLabel)", values: elementForm.values
        )
        store.appendElement(element, to: groupID)
        currentView = .list
        toast("“\(element.name)” added", color: .green)
    }

    func deleteElement(_ elementID: String) {
        guard let element = store.deleteElement(elementID, from: activeGroupID) else { return }
        revealedFieldKeys = revealedFieldKeys.filter { !$0.hasPrefix("\(elementID).") }
        watchedElementIDs.remove(elementID)
        currentView = .list
        toast("“\(element.name)” deleted", color: .red)
    }

    // MARK: - Actions: new/edit group

    func saveGroup() {
        let name = groupForm.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            toast("name the group first", color: .red)
            return
        }

        if let editingID = groupForm.editingGroupID {
            updateGroup(editingID, name: name)
            return
        }

        let groupID = GroupFormModel.slug(name)
        guard workspace.groups[groupID] == nil else {
            toast("group already exists", color: .red)
            return
        }
        let fields = GroupFormModel.normalisedFields(groupForm.fields)
        guard let firstField = fields.first else {
            toast("add at least one field", color: .red)
            return
        }
        store.addGroup(NBGroup(
            id: groupID, label: name.lowercased(),
            singular: GroupFormModel.singularise(name),
            secondaryKey: firstField.key, fields: fields, elements: []
        ))
        activeGroupID = groupID
        currentView = .list
        toast("group “\(name)” created", color: .green)
    }

    /// Applies the edited schema (the store handles value preservation and Keychain
    /// cleanup) and returns to the list.
    private func updateGroup(_ groupID: String, name: String) {
        guard store.applySchema(to: groupID, name: name, fields: groupForm.fields) else {
            toast("add at least one field", color: .red)
            return
        }
        groupForm.editingGroupID = nil
        currentView = .list
        toast("group “\(name)” updated", color: .green)
    }

    func deleteGroup(_ groupID: String) {
        guard let group = store.deleteGroup(groupID) else { return }
        if activeGroupID == groupID {
            activeGroupID = workspace.groupOrder.first ?? ""
        }
        groupForm.editingGroupID = nil
        currentView = .list
        toast("group “\(group.label)” deleted", color: .red)
    }

    // MARK: - Actions: collections

    /// Returns the panel to a coherent state after the catalogue under it changed
    /// wholesale (collection switch/delete, import, seed adoption).
    private func resetTransientUIState() {
        currentView = .list
        searchText = ""
        revealedFieldKeys = []
        keyboardSelectionID = nil
        elementForm.editingElementID = nil
        groupForm.editingGroupID = nil
        dismissClaimTooltip()
    }

    /// Shared tail of every path that swaps the catalogue under the panel.
    private func settleAfterCatalogueChange() {
        resetTransientUIState()
        activeGroupID = workspace.groupOrder.first ?? ""
    }

    func switchCollection(_ id: String) {
        guard id != activeCollectionID, store.contains(id) else { return }
        activeCollectionID = id
        settleAfterCatalogueChange()
    }

    func createCollection(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            toast("name the collection first", color: .red)
            return
        }
        store.create(named: trimmed)
        settleAfterCatalogueChange()
        toast("“\(trimmed)” created — \(hotKeyModifier.symbolPrefix)N adds your first element", color: .green)
    }

    func renameActiveCollection(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            toast("a collection needs a name", color: .red)
            return
        }
        store.renameActive(to: trimmed)
        toast("renamed to “\(trimmed)”", color: .green)
    }

    func duplicateActiveCollection() {
        let copy = store.duplicateActive()
        settleAfterCatalogueChange()
        toast("duplicated as “\(copy.name)”", color: .green)
    }

    func deleteActiveCollection() {
        let doomedID = activeCollectionID
        guard let deleted = store.deleteActive() else {
            toast("this is the only collection — create another before deleting it", color: .red)
            return
        }
        // Deleting a room-joined collection also leaves the room: a session for a
        // catalogue that no longer exists would keep publishing nothing and holding a
        // password this Mac has no use for.
        if let room = deleted.room {
            syncEngine?.leaveRoom(collectionID: doomedID)
            RoomKeyStore.deletePasswords(for: room)
        }
        settleAfterCatalogueChange()
        toast("collection “\(deleted.name)” deleted", color: .red)
    }

    // MARK: - Actions: import/export

    /// Replaces the active collection's catalogue with an imported one (onboarding's
    /// "import a collection file" starting point — the seeded placeholder is what dies).
    /// The trust boundary lives in the import pipeline (WorkspaceTransfer): in-band secret
    /// values are force-blanked there, real ones only enter via the encrypted envelope, and
    /// claims are stripped — so what arrives here is adopted as-is.
    func replaceActiveCollection(with imported: NBWorkspace) {
        store.replaceActive(with: imported)
        settleAfterCatalogueChange()
        // Watches on the discarded catalogue's elements can never fire — drop only those.
        watchedElementIDs = watchedElementIDs.intersection(store.elementIDs())
        toast("imported “\(workspace.name)” · \(workspace.elementCount) elements", color: .green)
    }

    /// Imports as a new collection alongside the existing ones — the menu path. Nothing is
    /// destroyed. Same trust posture as `replaceActiveCollection`.
    func addCollection(_ imported: NBWorkspace, deeplinkScheme: String = "") {
        let added = store.add(imported, deeplinkScheme: deeplinkScheme)
        settleAfterCatalogueChange()
        toast("imported “\(added.name)” · \(added.workspace.elementCount) elements", color: .green)
    }

    /// Adopts a freshly-seeded catalogue (onboarding's "sample" and "empty" starting
    /// points). Shares the replace path so the reset behaviour can't drift.
    func adoptSeedWorkspace(_ seeded: NBWorkspace) {
        store.replaceActive(with: seeded)
        settleAfterCatalogueChange()
        watchedElementIDs = watchedElementIDs.intersection(store.elementIDs())
    }

    /// Replaces every collection from a decrypted snapshot — the §14.5.2 recovery path.
    func restoreCollections(_ incoming: [NBCollection], activeID: String) {
        guard store.restore(incoming, activeID: activeID) else {
            toast("that snapshot is empty — nothing restored", color: .red)
            return
        }
        settleAfterCatalogueChange()
        watchedElementIDs = []
        toast("restored \(collections.count) collection\(collections.count == 1 ? "" : "s") from snapshot", color: .green)
    }

    // MARK: - Toasts

    func toast(_ message: String, color: NBToastColor) {
        toastCenter.post(message, color: color)
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

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
