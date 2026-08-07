//
//  EnvironmentWarningDialog.swift
//  notchboard
//
//  The speed bump between "this account works in staging" and "…and in production".
//
//  Mixing PRD with any other environment on one element is legitimate but risky: the same
//  row then hands production credentials to whatever build is pointed at it, and "login on
//  sim" will happily fire them into a debug app. That is how a real customer's data ends
//  up in a test session and how a prod token ends up in a screenshot. So it's allowed, and
//  it costs one deliberate confirmation.
//
//  NSAlert's own suppression button is the mechanism — the macOS-native "don't ask again",
//  which users already recognise. The answer is persisted (vision.md: it's a setting, not
//  session state), so ticking it means never again rather than never again today.
//

import AppKit

@MainActor
enum EnvironmentWarningDialog {
    struct Answer {
        let confirmed: Bool
        let suppressFuture: Bool
    }

    static func confirmProductionMix(elementName: String) -> Answer {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Use production alongside another environment?"
        let subject = elementName.trimmingCharacters(in: .whitespacesAndNewlines)
        alert.informativeText = """
        \(subject.isEmpty ? "This element" : "“\(subject)”") would carry PRD credentials into dev or staging work. Anything that reads it — including “login on sim” — can fire real production credentials at a debug build, and they can end up in logs, screenshots and shared test sessions.

        Keep production on its own element unless you genuinely need both.
        """
        alert.addButton(withTitle: "I understand")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Never show this warning again"

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        return Answer(
            confirmed: response == .alertFirstButtonReturn,
            suppressFuture: alert.suppressionButton?.state == .on
        )
    }
}
