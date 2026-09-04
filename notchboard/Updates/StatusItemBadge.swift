//
//  StatusItemBadge.swift
//  notchboard
//
//  The two menu-bar images: the brand glyph, and the same glyph with a dot while an update
//  waits (vision.md §13.20). Both are built once and the tick swaps them behind an equality
//  guard (AppDelegate.syncUpdateAffordances), so nothing is allocated per tick. Template images,
//  so the dot takes the menu-bar tint like the glyph does. Static by construction: the
//  no-continuous-animation rule applies to the menu bar as much as to the panel.
//

import AppKit

enum StatusItemBadge {
    static let symbolName = "square.righthalf.filled"

    static let plain: NSImage? = makeSymbol(description: "Notchboard")
    static let withDot: NSImage? = makeDotted()

    private static func makeSymbol(description: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        image?.isTemplate = true
        return image
    }

    /// Same canvas as the plain glyph, so the status item never shifts when the dot appears.
    /// A ring is knocked out of the glyph's corner first so the dot reads as a separate mark.
    private static func makeDotted(diameter: CGFloat = 4) -> NSImage? {
        guard let symbol = makeSymbol(description: "Notchboard") else { return nil }
        let image = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            let ring = NSRect(
                x: rect.maxX - diameter - 1, y: rect.maxY - diameter - 1,
                width: diameter + 2, height: diameter + 2
            )
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: ring).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: ring.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Notchboard, update available"
        return image
    }
}
