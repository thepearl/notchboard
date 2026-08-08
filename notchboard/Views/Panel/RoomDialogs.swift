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
        /// without auth. Its username lives inside `config.brokerURL`.
        let brokerPassword: String?
    }

    /// Sets up (or re-points) a collection's room: broker address, room name, the broker
    /// account pair when the broker requires one, and the room password. Loops until
    /// usable or cancelled. Storing and joining are the caller's job.
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
            Everyone who joins this room shares the catalogue live. Enter the address of a \
            real MQTT broker your team can reach (mqtts:// for TLS, wss:// through \
            corporate firewalls). Managed brokers like HiveMQ Cloud need the account \
            credentials they gave you — leave those two fields empty for brokers without \
            auth. Address, room name and account username travel inside exports; the two \
            passwords are shared out of band, like wifi.
            """
            alert.addButton(withTitle: "Join Room")
            alert.addButton(withTitle: "Cancel")

            let broker = PromptAccessory.makeField(NSTextField(), placeholder: "mqtts://your-broker:8883")
            broker.stringValue = brokerText
            let room = PromptAccessory.makeField(NSTextField(), placeholder: "room name, e.g. acme-mobile")
            room.stringValue = roomText
            let accountUser = PromptAccessory.makeField(NSTextField(), placeholder: "broker username (if any)")
            accountUser.stringValue = userText
            let accountPassword = PromptAccessory.makeField(NSSecureTextField(), placeholder: "broker password (if any)")
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

    /// The §14.3 moment: an imported file carried a room address. Returns the typed
    /// passwords, nil to stay local (the collection still imports either way). The
    /// broker-account field only appears when the address actually carries a username.
    static func promptToJoinImportedRoom(room: NBRoomConfig, memberName: String) -> (roomPassword: String, brokerPassword: String?)? {
        let accountUser = URL(string: room.brokerURL)?.user(percentEncoded: false)

        let alert = NSAlert()
        alert.messageText = "Join the “\(room.room)” room as \(memberName.isEmpty ? "yourself" : memberName)?"
        alert.informativeText = """
        This collection syncs through \(room.brokerHost ?? room.brokerURL). Enter the room \
        password — whoever shared the file has it\(accountUser.map { " — and the broker password for “\($0)”" } ?? "") \
        — and edits and in-use marks flow both ways, live. Skip to keep the catalogue \
        local; you can join later from the ▾ menu.
        """
        alert.addButton(withTitle: "Join")
        alert.addButton(withTitle: "Not Now")

        let roomPassword = PromptAccessory.makeField(NSSecureTextField(), placeholder: "room password")
        let accountPassword = accountUser.map { _ in
            PromptAccessory.makeField(NSSecureTextField(), placeholder: "broker password (account “\(accountUser ?? "")”)")
        }
        alert.accessoryView = PromptAccessory.roomJoin(accountPassword: accountPassword, roomPassword: roomPassword)
        alert.window.initialFirstResponder = accountPassword ?? roomPassword

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let password = roomPassword.stringValue.trimmingCharacters(in: .whitespaces)
        guard !password.isEmpty else { return nil }
        let broker = accountPassword?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
        return (password, broker.isEmpty ? nil : broker)
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
