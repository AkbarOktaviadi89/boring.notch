//
//  Constants.swift
//  boringNotch
//
//  Created by Richard Kunkli on 16/08/2024.
//

import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let clipboardHistoryPanel = Self("clipboardHistoryPanel", default: .init(.c, modifiers: [.shift, .command]))
    static let toggleMicrophone = Self("toggleMicrophone", default: .init(.f5, modifiers: [.function]))
    static let decreaseBacklight = Self("decreaseBacklight", default: .init(.f1, modifiers: [.command]))
    static let increaseBacklight = Self("increaseBacklight", default: .init(.f2, modifiers: [.command]))
    static let toggleSneakPeek = Self("toggleSneakPeek", default: .init(.h, modifiers: [.command, .shift]))
    static let toggleNotchOpen = Self("toggleNotchOpen", default: .init(.i, modifiers: [.command, .shift]))
    // Opens Dev Tools with the clipboard loaded. ⌃⌥⌘ because ⌥⌘D already shows and hides the Dock.
    static let openDevTools = Self("openDevTools", default: .init(.d, modifiers: [.control, .option, .command]))
    // ⌃⌥Space is taken by macOS for switching input sources, so capture follows the ⌃⌥⌘ family as well
    static let clipboardHistory = Self("clipboardHistory", default: .init(.v, modifiers: [.control, .option, .command]))
    static let translate = Self("translate", default: .init(.l, modifiers: [.control, .option, .command]))
    static let copyTextFromScreen = Self("copyTextFromScreen", default: .init(.t, modifiers: [.control, .option, .command]))
    static let quickCapture = Self("quickCapture", default: .init(.n, modifiers: [.control, .option, .command]))
}
