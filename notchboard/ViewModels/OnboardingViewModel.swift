//
//  OnboardingViewModel.swift
//  notchboard
//

import Foundation
import Observation

/// How a new user's first catalogue gets filled. A team is an upgrade, not a
/// prerequisite — but since the room landed, joining one IS a starting point: paste the
/// invite a teammate sent, type the room password, and the team's catalogue is yours
/// (vision.md §14.3, revised 2026-08-08).
enum NBStartingPoint: String, CaseIterable, Identifiable {
    case sample
    case empty
    case importFile
    case joinTeam

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sample: return "sample catalogue"
        case .empty: return "empty catalogue"
        case .importFile: return "import a collection file"
        case .joinTeam: return "join a team room"
        }
    }

    var detail: String {
        switch self {
        case .sample: return "4 groups · 20 elements to poke at"
        case .empty: return "one “users” group, nothing in it"
        case .importFile: return "exported from another mac · secrets aren't included"
        case .joinTeam: return "paste the invite a teammate sent · one password"
        }
    }

    var glyph: String {
        switch self {
        case .sample: return "▣"
        case .empty: return "＋"
        case .importFile: return "⇥"
        case .joinTeam: return "⇄"
        }
    }

    var ctaLabel: String {
        switch self {
        case .sample: return "load sample data →"
        case .empty: return "start empty →"
        case .importFile: return "choose file →"
        case .joinTeam: return "join the room →"
        }
    }
}

@Observable
final class OnboardingViewModel {
    var isPresented: Bool = true
    var step: Int = 1
    var name: String = ""
    var accessibilityGranted: Bool = false
    /// Which starting point the user picked on step 3. Sample is the default because an
    /// empty panel teaches nothing on first launch.
    var startingPoint: NBStartingPoint = .sample
    /// The join-a-team starting point's two inputs. Held here, applied by the scene's
    /// applyStartingPoint — the same seam every other starting point goes through.
    var inviteText: String = ""
    var roomPassword: String = ""

    var initials: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }
        return trimmed.split(separator: " ").compactMap { $0.first }.prefix(2).map(String.init).joined().uppercased()
    }

    var firstNameLowercased: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.split(separator: " ").first else { return "you" }
        return first.lowercased()
    }

    func reset() {
        isPresented = true
        step = 1
        name = ""
        accessibilityGranted = false
        startingPoint = .sample
        inviteText = ""
        roomPassword = ""
    }

    enum AdvanceResult {
        case advanced
        case finished
        case error(String)
    }

    /// Validates the current step and either advances, signals completion, or returns an error message.
    func advance() -> AdvanceResult {
        switch step {
        case 1:
            step = 2
            return .advanced
        case 2:
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .error("enter your name — it labels what you mark in use")
            }
            step = 3
            return .advanced
        case 3:
            // No gate. Step 3 used to demand an invite code of six or more characters, which
            // made a team a hard prerequisite for using the app at all. Choosing a starting
            // point is now the whole job, and the view has already applied it by this point.
            step = 4
            return .advanced
        case 4:
            guard accessibilityGranted else {
                return .error("grant accessibility access first")
            }
            return .finished
        default:
            return .advanced
        }
    }

    func back() {
        step = max(1, step - 1)
    }

    /// Polls a trust probe until it reports granted or the surrounding task is cancelled.
    /// The permission step's `.task` runs this while the step is visible; the user grants
    /// access in System Settings, outside our window, so there's no callback to observe.
    ///
    /// Cancellation must exit the loop: `Task.sleep` throws `CancellationError` once the
    /// task is cancelled, and swallowing that (`try?`) turns the poll into a zero-delay
    /// main-actor spin for the rest of the session — a real bug this replaced.
    func pollAccessibility(
        probe: () -> Bool = { AccessibilityPermission.isTrusted },
        interval: Duration = .milliseconds(500)
    ) async {
        while !accessibilityGranted && !Task.isCancelled {
            accessibilityGranted = probe()
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
        }
    }
}
