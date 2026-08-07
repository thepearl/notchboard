//
//  UTTypeNotchboard.swift
//  notchboard
//
//  The collection file's type identity, declared (exported) in the root Info.plist so
//  Finder can associate .notchboard files with the app — double-click and "Open With"
//  route into AppDelegate.application(_:open:).
//

import UniformTypeIdentifiers

extension UTType {
    /// ".notchboard" is the extension — deliberately single-dot, because LaunchServices
    /// resolves multi-dot extensions by their last component and could never associate a
    /// ".something.json" spelling with anything but a JSON handler.
    static let notchboardCollection = UTType(exportedAs: "com.flourix.notchboard.collection")
}
