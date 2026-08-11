//
//  NBMetrics.swift
//  notchboard
//

import Foundation

/// Shared layout constants transcribed from the prototype's px values.
enum NBMetrics {
    static let panelWidth: CGFloat = 404
    static let panelHeight: CGFloat = 592
    static let panelCornerRadius: CGFloat = 10
    static let rowCornerRadius: CGFloat = 3
    static let cardCornerRadius: CGFloat = 6

    // 28×150 → 36×62 after several rounds of team feedback: wider (a 28pt tab was a
    // fiddly click target) but much shorter — just the dot and the chevron, packed
    // together. It also sits 10pt below the Simulator window's vertical centre
    // (AppDelegate.notchVerticalOffset).
    static let notchWidth: CGFloat = 36
    static let notchHeight: CGFloat = 62

    /// One height for the search field and the buttons that sit beside it — "exactly the
    /// same" was literal feedback.
    static let controlHeight: CGFloat = 34
    static let coachMarkWidth: CGFloat = 198

    static let toastCornerRadius: CGFloat = 5
}
