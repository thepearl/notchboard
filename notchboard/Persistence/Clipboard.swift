//
//  Clipboard.swift
//  notchboard
//
//  Copying with a shelf life. Secret values go onto the general pasteboard like anything
//  else, so two things happen that don't for ordinary text:
//
//  - the entry is marked with the standard concealed-type hint (nspasteboard.org), which
//    cooperating clipboard managers honour by not recording it, and
//  - it is cleared after a minute, unless the user has copied something else since — the
//    hint is advisory, and without this the plaintext would sit on the pasteboard until
//    the next copy, which might be tomorrow.
//

import Foundation
#if canImport(AppKit)
import AppKit
#endif

final class Clipboard {
    /// How long a concealed copy is allowed to live on the pasteboard.
    static let concealedLifetime: Duration = .seconds(60)

    private var clearTask: Task<Void, Never>?

    deinit {
        clearTask?.cancel()
    }

    func copy(_ text: String, concealed: Bool) {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        guard concealed else { return }

        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        let changeCount = pasteboard.changeCount
        clearTask?.cancel()
        clearTask = Task {
            try? await Task.sleep(for: Self.concealedLifetime)
            guard !Task.isCancelled else { return }
            // Only clear if our copy is still what's on the pasteboard — never wipe
            // something the user copied afterwards.
            let current = NSPasteboard.general
            if current.changeCount == changeCount {
                current.clearContents()
            }
        }
        #endif
    }
}
