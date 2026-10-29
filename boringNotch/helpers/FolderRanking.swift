//
//  FolderRanking.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import Foundation

/// How often and how recently a folder was opened, from Spotlight (Finder records it) and from the panel itself
struct FolderUsage: Equatable {
    let path: String
    var lastUsed: Date
    var useCount: Int
}

/// A folder the user pinned. The bookmark lets the sandboxed app open it and copy files into it.
struct PinnedFolder: Codable, Equatable, Identifiable {
    var id: String { path }
    let path: String
    let bookmark: Data?
}

/// One row of the Folders panel
struct ListedFolder: Equatable, Identifiable {
    var id: String { path }
    let path: String
    let isPinned: Bool

    var name: String { (path as NSString).lastPathComponent }
}

/// Which folders the panel offers and in what order. Foundation only, so it can be tested without the app.
enum FolderRanking {
    static let limit = 15
    /// Spotlight's window for "recently used"
    static let lookbackDays = 30

    /// Folders full of generated or system files: opening them is rarely the point
    private static let skippedNames: Set<String> = [
        "Library", "node_modules", "DerivedData", "Pods", "vendor", "__pycache__", "venv", "build", "dist",
    ]
    /// Bundles look like folders but are opened as documents
    private static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "xcodeproj", "xcworkspace", "photoslibrary", "musiclibrary", "pages", "numbers", "key",
        "rtfd", "playground", "xcassets", "lproj", "plugin", "kext",
    ]

    /// Inside the home folder, not the home folder itself, nothing hidden, generated or inside a package
    static func isWorthListing(_ path: String, home: String) -> Bool {
        let home = home.hasSuffix("/") ? String(home.dropLast()) : home
        guard path.hasPrefix(home + "/") else { return false }
        let components = path.dropFirst(home.count + 1).split(separator: "/").map(String.init)
        guard !components.isEmpty else { return false }
        for component in components {
            if component.hasPrefix(".") || skippedNames.contains(component) { return false }
            let ext = (component as NSString).pathExtension.lowercased()
            if !ext.isEmpty, packageExtensions.contains(ext) { return false }
        }
        return true
    }

    /// The helper's report: one "path<TAB>last used (seconds since 1970)<TAB>use count" line per folder
    static func parse(_ report: String) -> [FolderUsage] {
        report.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3, let seconds = Double(fields[1]), let count = Int(fields[2]), !fields[0].isEmpty else { return nil }
            return FolderUsage(path: String(fields[0]), lastUsed: Date(timeIntervalSince1970: seconds), useCount: count)
        }
    }

    /// Often and lately both count: each open is worth less the older the last one is
    static func score(_ usage: FolderUsage, now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(usage.lastUsed) / 86_400)
        return Double(usage.useCount + 1) / (1 + days / 3)
    }

    /// Spotlight's numbers plus opens from the panel, per folder
    static func merge(_ spotlight: [FolderUsage], _ own: [FolderUsage]) -> [FolderUsage] {
        var byPath: [String: FolderUsage] = [:]
        for usage in spotlight + own {
            if var existing = byPath[usage.path] {
                existing.useCount += usage.useCount
                existing.lastUsed = max(existing.lastUsed, usage.lastUsed)
                byPath[usage.path] = existing
            } else {
                byPath[usage.path] = usage
            }
        }
        return Array(byPath.values)
    }

    /// Pinned folders first, in the order they were pinned, then the best scoring others.
    /// Removed folders stay out; the query narrows by name and path.
    static func list(pinned: [String], usage: [FolderUsage], hidden: Set<String>, home: String,
                     now: Date, query: String = "", limit: Int = limit) -> [ListedFolder] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        func matches(_ path: String) -> Bool {
            words.allSatisfy { path.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        let pinnedRows = pinned.filter(matches).map { ListedFolder(path: $0, isPinned: true) }
        let pinnedSet = Set(pinned)
        let others = usage
            .filter { !pinnedSet.contains($0.path) && !hidden.contains($0.path) && isWorthListing($0.path, home: home) && matches($0.path) }
            .sorted { score($0, now: now) != score($1, now: now) ? score($0, now: now) > score($1, now: now) : $0.path < $1.path }
            .prefix(max(0, limit - pinnedRows.count))
            .map { ListedFolder(path: $0.path, isPinned: false) }
        return pinnedRows + others
    }

    /// "~/Data/Algonova" for the folder's parent
    static func displayParent(of path: String, home: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        let home = home.hasSuffix("/") ? String(home.dropLast()) : home
        if parent == home { return "~" }
        return parent.hasPrefix(home + "/") ? "~" + parent.dropFirst(home.count) : parent
    }
}
