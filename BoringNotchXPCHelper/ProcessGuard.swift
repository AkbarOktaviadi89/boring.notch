//
//  ProcessGuard.swift
//  BoringNotchXPCHelper
//
//  Created by Akbar Oktaviadi on 2026-10-28.
//

import Foundation

/// Which processes the notch may force quit. Compiled into both the app (to show the button)
/// and the helper (which checks again before it sends the signal). Foundation only, so it can be tested.
enum ProcessGuard {
    /// Separates the ps part of the app usage report from the top part
    static let reportSeparator = "@@BORING-NOTCH-TOP@@"

    /// macOS itself: killing these logs the user out, restarts the Dock or Finder, or worse.
    /// /usr/local stays allowed, it holds Homebrew tools on Intel Macs.
    private static let protectedPrefixes = [
        "/System/Library/", "/System/Cryptexes/", "/usr/bin/", "/usr/sbin/", "/usr/libexec/", "/usr/lib/",
        "/bin/", "/sbin/", "/Library/Apple/",
    ]

    static func canForceQuit(path: String, uid: UInt32, currentUID: UInt32) -> Bool {
        guard uid == currentUID, path.hasPrefix("/") else { return false }
        if protectedPrefixes.contains(where: path.hasPrefix) { return false }
        // Not the notch itself
        return !path.contains("/Boring Notch.app/")
    }
}
