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

    /// Sets up (or re-points) a collection's room: broker address, room name, password.
    /// Loops until the three are usable or the user cancels. Returns the validated config
    /// plus the password — storing and joining are the caller's job.
    static func promptForRoomSetup(collectionName: String, current: NBRoomConfig?) -> (config: NBRoomConfig, password: String)? {
        var complaint: String?
        var brokerText = current?.brokerURL ?? ""
        var roomText = current?.room ?? ""

        while true {
            let alert = NSAlert()
            alert.messageText = "Team room for “\(collectionName)”"
            // No example hostname anywhere in this dialog, learned the hard way: the
            // first real user typed the example in verbatim and got a red dot and a
            // ten-second timeout. The address has to come from an actual broker.
            alert.informativeText = complaint ?? """
            Everyone who joins this room shares the catalogue live. Enter the address of a \
            real MQTT broker your team can reach — one you run, or a managed one \
            (mqtts:// for TLS, wss:// through corporate firewalls). The address and room \
            name travel inside exports; the password is shared out of band, like wifi.
            """
            alert.addButton(withTitle: "Join Room")
            alert.addButton(withTitle: "Cancel")

            let broker = PromptAccessory.makeField(NSTextField(), placeholder: "mqtts://your-broker:8883")
            broker.stringValue = brokerText
            let room = PromptAccessory.makeField(NSTextField(), placeholder: "room name, e.g. acme-mobile")
            room.stringValue = roomText
            let password = PromptAccessory.makeField(NSTextField(), placeholder: "room password")
            let generate = NSButton(title: "Generate", target: nil, action: nil)
            let target = GeneratePassphraseTarget(field: password)
            generate.target = target
            generate.action = #selector(GeneratePassphraseTarget.generate)
            generate.bezelStyle = .rounded

            alert.accessoryView = PromptAccessory.roomSetup(broker: broker, room: room, password: password, generate: generate)
            alert.window.initialFirstResponder = broker

            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            withExtendedLifetime(target) {}

            brokerText = broker.stringValue.trimmingCharacters(in: .whitespaces)
            roomText = room.stringValue
            let passwordText = password.stringValue.trimmingCharacters(in: .whitespaces)

            var candidate = NBRoomConfig(brokerURL: brokerText, room: "")
            guard candidate.brokerHost != nil,
                  ["mqtts", "wss", "mqtt"].contains(URL(string: brokerText)?.scheme ?? "") else {
                complaint = "That broker address doesn't parse — mqtts://host:8883 or wss://host/mqtt."
                continue
            }
            guard let slug = NBRoomConfig.normalisedSlug(roomText) else {
                complaint = "Room names are lowercase letters, digits and dashes — e.g. acme-mobile."
                continue
            }
            guard !passwordText.isEmpty else {
                complaint = "The room password seals every payload — it can't be empty. Generate makes a strong one."
                continue
            }
            candidate.room = slug
            return (candidate, passwordText)
        }
    }

    /// The §14.3 moment: an imported file carried a room address. Returns the typed
    /// password, nil to stay local (the collection still imports either way).
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

        let field = PromptAccessory.makeField(NSSecureTextField(), placeholder: "room password")
        alert.accessoryView = PromptAccessory.password(field: field)
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let password = field.stringValue.trimmingCharacters(in: .whitespaces)
        return password.isEmpty ? nil : password
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
