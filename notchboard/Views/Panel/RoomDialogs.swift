//
//  RoomDialogs.swift
//  notchboard
//
//  AppKit prompts for the team room (vision.md §14.3): setting one up, joining one that
//  arrived inside an imported file, and leaving. Same pattern as CollectionDialogs —
//  NSAlert, NSApp.activate first, and PromptAccessory's fixed-frame containers (never
//  NSStackView; see WorkspaceTransferFlows for the collapse bug that rule comes from).
//
//  Copy rules that apply here with extra force: the password field for CREATING a room
//  shows its text (a passphrase you can't read is one you can't share, and sharing it is
//  the point — like the export prompt); the password field for JOINING is secure (you're
//  typing a known secret, not minting one). And "claim" never appears.
//

import AppKit

@MainActor
enum RoomDialogs {

    struct RoomSetup {
        let config: NBRoomConfig
        let roomPassword: String
        /// The broker account's password (HiveMQ Cloud and friends); nil for brokers
        /// without auth. Its username lives inside `config.brokerURL`. Plaintext exactly
        /// here and in the engine's hand-off to the transport — the engine seals it into
        /// the config, and from then on it travels only as ciphertext.
        let brokerPassword: String?
    }

    /// Sets up (or re-points) a collection's room. This is the ONE dialog where broker
    /// details get typed, by one person, once — everyone else joins from the invite,
    /// which carries all of it (the account password sealed under the room key).
    /// Loops until usable or cancelled. Storing and joining are the caller's job.
    static func promptForRoomSetup(collectionName: String, current: NBRoomConfig?) -> RoomSetup? {
        var complaint: String?
        var brokerText = current?.brokerURL ?? ""
        var roomText = current?.room ?? ""
        var userText = current.flatMap { URL(string: $0.brokerURL)?.user(percentEncoded: false) } ?? ""

        while true {
            let alert = NSAlert()
            alert.messageText = "Team room for “\(collectionName)”"
            // No example hostname anywhere in this dialog, learned the hard way: the
            // first real user typed the example in verbatim and got a red dot and a
            // ten-second timeout. The address has to come from an actual broker.
            alert.informativeText = complaint ?? """
            Only you fill this in — teammates just paste the invite you copy afterwards. \
            Use your MQTT broker's address (mqtts:// for TLS, wss:// through firewalls). \
            The account fields are for managed brokers like HiveMQ Cloud; leave them \
            empty otherwise. Share the room password out of band, like wifi.
            """
            alert.addButton(withTitle: "Join Room")
            alert.addButton(withTitle: "Cancel")

            let broker = PromptAccessory.makeField(NSTextField(), placeholder: "mqtts://your-broker:8883")
            broker.stringValue = brokerText
            let room = PromptAccessory.makeField(NSTextField(), placeholder: "room name, e.g. acme-mobile")
            room.stringValue = roomText
            let accountUser = PromptAccessory.makeField(NSTextField(), placeholder: "broker username (if any)")
            accountUser.stringValue = userText
            let accountPassword = PromptAccessory.makeField(
                NSSecureTextField(),
                // Re-pointing an existing auth room keeps the sealed credential when
                // this stays blank (the view model carries it forward) — say so.
                placeholder: current?.sealedBrokerPassword != nil
                    ? "broker password (blank = keep current)"
                    : "broker password (if any)"
            )
            let password = PromptAccessory.makeField(NSTextField(), placeholder: "room password")
            let generate = NSButton(title: "Generate", target: nil, action: nil)
            let target = GeneratePassphraseTarget(field: password)
            generate.target = target
            generate.action = #selector(GeneratePassphraseTarget.generate)
            generate.bezelStyle = .rounded

            alert.accessoryView = PromptAccessory.roomSetup(
                broker: broker, room: room,
                accountUser: accountUser, accountPassword: accountPassword,
                password: password, generate: generate
            )
            alert.window.initialFirstResponder = broker

            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            withExtendedLifetime(target) {}

            brokerText = broker.stringValue.trimmingCharacters(in: .whitespaces)
            roomText = room.stringValue
            userText = accountUser.stringValue.trimmingCharacters(in: .whitespaces)
            let accountPasswordText = accountPassword.stringValue.trimmingCharacters(in: .whitespaces)
            let passwordText = password.stringValue.trimmingCharacters(in: .whitespaces)

            // The username rides in the URL (it's team-shared, like the address) —
            // URLComponents percent-encodes it and replaces whatever was pasted in.
            guard var components = URLComponents(string: brokerText),
                  let host = components.host, !host.isEmpty,
                  ["mqtts", "wss", "mqtt"].contains(components.scheme ?? "") else {
                complaint = "That broker address doesn't parse — mqtts://host:8883 or wss://host/mqtt."
                continue
            }
            components.user = userText.isEmpty ? nil : userText
            components.password = nil // never in the URL, never in a file
            guard let finalURL = components.string else {
                complaint = "That broker address doesn't parse — mqtts://host:8883 or wss://host/mqtt."
                continue
            }
            guard let slug = NBRoomConfig.normalisedSlug(roomText) else {
                complaint = "Room names are lowercase letters, digits and dashes — e.g. acme-mobile."
                continue
            }
            guard accountPasswordText.isEmpty || !userText.isEmpty else {
                complaint = "A broker password needs its username — both are on the broker's access page."
                continue
            }
            guard !passwordText.isEmpty else {
                complaint = "The room password seals every payload — it can't be empty. Generate makes a strong one."
                continue
            }
            return RoomSetup(
                config: NBRoomConfig(brokerURL: finalURL, room: slug),
                roomPassword: passwordText,
                brokerPassword: accountPasswordText.isEmpty ? nil : accountPasswordText
            )
        }
    }

    /// The §14.3 moment: an imported file carried a room address. Returns the typed room
    /// password — the only secret a joiner ever needs (the broker credential rides sealed
    /// inside the config) — or nil to stay local (the collection imports either way).
    static func promptToJoinImportedRoom(room: NBRoomConfig, memberName: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Join the “\(room.room)” room as \(memberName.isEmpty ? "yourself" : memberName)?"
        alert.informativeText = """
        This collection syncs through \(room.brokerHost ?? room.brokerURL). Enter the room \
        password — whoever shared the file has it — and edits and in-use marks flow both \
        ways, live. Skip to keep the catalogue local; you can join later from the ▾ menu.
        """
        alert.addButton(withTitle: "Join")
        alert.addButton(withTitle: "Not Now")

        let roomPassword = PromptAccessory.makeField(NSSecureTextField(), placeholder: "room password")
        alert.accessoryView = PromptAccessory.password(field: roomPassword)
        alert.window.initialFirstResponder = roomPassword

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let password = roomPassword.stringValue.trimmingCharacters(in: .whitespaces)
        return password.isEmpty ? nil : password
    }

    /// The front door for invitees: paste the one-line invite a teammate sent, type the
    /// room password, done. Loops on a bad paste rather than dumping the user back to
    /// the menu. Returns nil on cancel.
    static func promptToJoinWithInvite(memberName: String) -> (config: NBRoomConfig, roomPassword: String)? {
        var complaint: String?
        var inviteText = ""

        while true {
            let alert = NSAlert()
            alert.messageText = "Join a team room\(memberName.isEmpty ? "" : " as \(memberName)")"
            alert.informativeText = complaint ?? """
            Paste the invite a teammate copied from their ▾ menu (it starts with \
            “notchboard-room:”), and the room password they shared separately. The room's \
            catalogue replaces this collection's — your local copy is snapshotted first.
            """
            alert.addButton(withTitle: "Join")
            alert.addButton(withTitle: "Cancel")

            let invite = PromptAccessory.makeField(NSTextField(), placeholder: "notchboard-room:…")
            invite.stringValue = inviteText
            let roomPassword = PromptAccessory.makeField(NSSecureTextField(), placeholder: "room password")
            alert.accessoryView = PromptAccessory.inviteJoin(invite: invite, password: roomPassword)
            alert.window.initialFirstResponder = inviteText.isEmpty ? invite : roomPassword

            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }

            inviteText = invite.stringValue
            guard let config = RoomInvite.decode(inviteText) else {
                complaint = "That doesn't decode as a notchboard invite — paste the whole “notchboard-room:…” line."
                continue
            }
            let password = roomPassword.stringValue.trimmingCharacters(in: .whitespaces)
            guard !password.isEmpty else {
                complaint = "The room password is the one secret the invite doesn't carry — ask whoever sent it."
                continue
            }
            return (config, password)
        }
    }

    static func confirmLeave(roomName: String, collectionName: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Leave the “\(roomName)” room?"
        alert.informativeText = "“\(collectionName)” keeps everything it has, but stops sending and receiving changes. The room password is removed from this Mac."
        alert.addButton(withTitle: "Leave Room")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
