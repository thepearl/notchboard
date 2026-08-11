//
//  ToastCenter.swift
//  notchboard
//
//  The bottom-right toast stack: post a message, it disappears on its own. Extracted from
//  NotchboardViewModel because every action in the app ends by saying something, so this
//  was the one piece of state touched by literally every other concern.
//

import Foundation
import Observation
import SwiftUI

struct NBToast: Identifiable, Equatable {
    let id: UUID
    let message: String
    let color: NBToastColor
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

@Observable
final class ToastCenter {
    /// Newest last. Capped so a burst (a multi-file import, an auto-release sweep) can't
    /// grow the stack past what fits above the panel's footer.
    private(set) var items: [NBToast] = []

    static let visibleLimit = 4
    static let lifetime: Duration = .seconds(2.8)

    func post(_ message: String, color: NBToastColor) {
        let item = NBToast(id: UUID(), message: message, color: color)
        items.append(item)
        if items.count > Self.visibleLimit {
            items.removeFirst(items.count - Self.visibleLimit)
        }
        // Each toast owns its own dismissal rather than a shared sweep timer: they expire
        // independently, and a timer would keep firing while the panel sits idle (see
        // vision.md §13.4 on why anything periodic in this window is suspect).
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.lifetime)
            self?.items.removeAll { $0.id == item.id }
        }
    }
}
