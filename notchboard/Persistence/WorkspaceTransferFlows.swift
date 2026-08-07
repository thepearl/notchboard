//
//  WorkspaceTransferFlows.swift
//  notchboard
//
//  The user-facing halves of export and import: the password prompts around
//  WorkspaceTransfer. Shared by the menu bar, onboarding's "import a collection" starting
//  point, and the double-click open path, so the trust boundary and the copy can't drift
//  between entry points.
//
//  Like WorkspaceFileDialogs, every prompt activates the app first — Notchboard is an
//  accessory agent, and an unactivated modal can open behind whatever the user is reading.
//

import AppKit

/// Keeps the Generate button's target alive for the duration of the modal — NSButton does
/// not retain its target.
private final class GeneratePassphraseTarget: NSObject {
    private let field: NSTextField
    init(field: NSTextField) { self.field = field }
    @objc func generate() {
        field.stringValue = PassphraseGenerator.generate()
    }
}

/// Accessory views for the prompts below, built with explicit frames inside a plain
/// container.
///
/// Deliberately NOT an NSStackView: a stack view lays its children out with Auto Layout,
/// and an empty NSTextField's intrinsic width is a few points, so the field collapsed to a
/// sliver next to the Generate button and the password was invisible. A container whose
/// subviews carry fixed frames can't do that.
enum PromptAccessory {
    static func passwordWithGenerate(field: NSTextField, generate: NSButton) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 338, height: 30))
        field.frame = NSRect(x: 0, y: 3, width: 232, height: 24)
        generate.frame = NSRect(x: 240, y: 0, width: 98, height: 30)
        container.addSubview(field)
        container.addSubview(generate)
        return container
    }

    static func password(field: NSTextField) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 338, height: 24))
        field.frame = NSRect(x: 0, y: 0, width: 338, height: 24)
        container.addSubview(field)
        return container
    }

    /// Single-line, non-wrapping, and wide enough for a full generated passphrase
    /// ("kw3ph-x87mn-qv2tc-e9rju") at the monospaced size below.
    static func makeField<T: NSTextField>(_ field: T, placeholder: String) -> T {
        field.placeholderString = placeholder
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        return field
    }
}

@MainActor
enum WorkspaceExportFlow {
    /// Asks for the mandatory export password (vision.md §14.5.1), offering a generated
    /// passphrase one click away. Returns nil when the user cancels; never returns empty.
    /// The field shows the password in the clear on purpose: a generated passphrase the
    /// user can't see is a passphrase they can't share, and sharing it is the point.
    static func promptForPassword(collectionName: String) -> String? {
        var complaint: String?
        while true {
            let alert = NSAlert()
            alert.messageText = "Set a password for “\(collectionName)”"
            alert.informativeText = complaint
                ?? "Exports always carry their secrets, encrypted. Whoever imports this file will need the password — share it separately from the file."
            alert.addButton(withTitle: "Export")
            alert.addButton(withTitle: "Cancel")

            let field = PromptAccessory.makeField(NSTextField(), placeholder: "export password")
            let generate = NSButton(title: "Generate", target: nil, action: nil)
            let target = GeneratePassphraseTarget(field: field)
            generate.target = target
            generate.action = #selector(GeneratePassphraseTarget.generate)
            generate.bezelStyle = .rounded

            alert.accessoryView = PromptAccessory.passwordWithGenerate(field: field, generate: generate)
            alert.window.initialFirstResponder = field

            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            withExtendedLifetime(target) {}

            let password = field.stringValue.trimmingCharacters(in: .whitespaces)
            if !password.isEmpty { return password }
            complaint = "A password is required — every export is encrypted. Use Generate if you don't want to invent one."
        }
    }
}

@MainActor
enum WorkspaceImportFlow {
    private enum PasswordChoice {
        case password(String)
        case skip
        case cancelled
    }

    /// The full interactive import: read and sanitise the file, then resolve its secrets —
    /// prompting for the password, re-prompting on a wrong one, and offering to import
    /// without secrets. Returns nil when the user cancels outright. Throws
    /// WorkspaceTransfer.ImportError for files that can't be imported at all.
    static func importInteractively(from url: URL) throws -> NBWorkspace? {
        guard let data = try? Data(contentsOf: url) else {
            throw WorkspaceTransfer.ImportError.unreadable
        }
        let file = try WorkspaceTransfer.readFile(from: data)
        guard file.secrets != nil else {
            // Secretless catalogue — nothing to unlock.
            return file.workspace
        }

        var wrongAttempt = false
        while true {
            switch promptForPassword(fileName: url.lastPathComponent, afterWrongAttempt: wrongAttempt) {
            case .cancelled:
                return nil
            case .skip:
                return file.workspace
            case .password(let password):
                do {
                    return try WorkspaceTransfer.unlockingSecrets(of: file, password: password)
                } catch WorkspaceTransfer.ImportError.wrongPassword {
                    wrongAttempt = true
                }
            }
        }
    }

    /// Toast copy for the errors the pipeline can throw. Wrong-password never escapes the
    /// interactive loop, so it isn't mapped.
    static func userMessage(for error: Error) -> String {
        switch error {
        case WorkspaceTransfer.ImportError.unreadable:
            return "import failed — not a notchboard collection file"
        case WorkspaceTransfer.ImportError.emptyWorkspace:
            return "import failed — the file contains no groups"
        case WorkspaceTransfer.ImportError.unsupportedVersion(let version):
            return "this file needs a newer notchboard (format v\(version))"
        default:
            return "import failed — \(error.localizedDescription)"
        }
    }

    private static func promptForPassword(fileName: String, afterWrongAttempt: Bool) -> PasswordChoice {
        let alert = NSAlert()
        alert.messageText = afterWrongAttempt
            ? "Wrong password for “\(fileName)”"
            : "“\(fileName)” carries encrypted secrets"
        alert.informativeText = afterWrongAttempt
            ? "That password doesn't open this file. Try again, or import without the secret values."
            : "Enter the password it was exported with, or import without secrets and fill them in later."
        alert.addButton(withTitle: "Unlock")
        alert.addButton(withTitle: "Import Without Secrets")
        alert.addButton(withTitle: "Cancel")

        let field = PromptAccessory.makeField(NSSecureTextField(), placeholder: "password")
        alert.accessoryView = PromptAccessory.password(field: field)
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .password(field.stringValue)
        case .alertSecondButtonReturn:
            return .skip
        default:
            return .cancelled
        }
    }
}
