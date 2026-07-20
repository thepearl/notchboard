//
//  FloatingPanel.swift
//  notchboard
//
//  A borderless, non-activating panel that can still become key so SwiftUI text fields,
//  focus state, and keyboard shortcuts (⌘K, Esc, etc.) work inside it — while never
//  stealing focus from Simulator/Xcode when it first appears or repositions.
//

import AppKit

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
