//
//  OnboardingViewModel.swift
//  notchboard
//

import Foundation
import Observation

@Observable
final class OnboardingViewModel {
    var isPresented: Bool = true
    var step: Int = 1
    var name: String = ""
    var code: String = ""
    var accessibilityGranted: Bool = false

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

    var codeLooksValid: Bool {
        code.trimmingCharacters(in: .whitespacesAndNewlines).count >= 6
    }

    func reset() {
        isPresented = true
        step = 1
        name = ""
        code = ""
        accessibilityGranted = false
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
                return .error("enter your name — it shows on claims")
            }
            step = 3
            return .advanced
        case 3:
            guard codeLooksValid else {
                return .error("paste an invite code from a teammate")
            }
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
}
