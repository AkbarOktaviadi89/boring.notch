//
//  ClipboardHistory.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import Foundation

/// One copied thing: text (links included) or an image saved next to the history
struct ClipEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String?
    /// File name in the history's image folder
    var imageFile: String?
    var imageWidth: Int?
    var imageHeight: Int?
    var sourceApp: String?
    var isPinned = false
    var copiedAt = Date()

    var isImage: Bool { imageFile != nil }

    var isLink: Bool {
        guard let text else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.contains(where: \.isWhitespace)
            && (trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://"))
    }
}

/// Ordering, de-duplication and search for the clipboard history. Foundation only, so it can be tested without the app.
enum ClipboardHistory {
    /// Unpinned entries kept; pinned ones don't count
    static let limit = 50
    /// Longer text (a whole file's worth) isn't kept
    static let maxTextLength = 100_000

    /// The new entry goes on top. Copying the same text again moves the old entry up and keeps its pin.
    /// Returns the list and the entries that fell off, so their images can be deleted.
    static func adding(_ entry: ClipEntry, to list: [ClipEntry]) -> (list: [ClipEntry], removed: [ClipEntry]) {
        var entry = entry
        var rest = list
        if let text = entry.text, let index = rest.firstIndex(where: { $0.text == text }) {
            entry.isPinned = rest[index].isPinned
            entry.id = rest[index].id
            rest.remove(at: index)
        }
        let combined = [entry] + rest
        var kept: [ClipEntry] = []
        var removed: [ClipEntry] = []
        var unpinned = 0
        for item in combined {
            if item.isPinned {
                kept.append(item)
            } else if unpinned < limit {
                kept.append(item)
                unpinned += 1
            } else {
                removed.append(item)
            }
        }
        return (kept, removed)
    }

    /// Pinned first, then the most recent
    static func ordered(_ list: [ClipEntry]) -> [ClipEntry] {
        list.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.copiedAt > rhs.copiedAt
        }
    }

    /// Every word must appear, ignoring case and accents. "image" finds images, the app name finds what it copied.
    static func search(_ list: [ClipEntry], query: String) -> [ClipEntry] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return ordered(list) }
        return ordered(list.filter { entry in
            let haystack = [entry.text, entry.sourceApp, entry.isImage ? "image" : nil].compactMap { $0 }.joined(separator: " ")
            return words.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        })
    }

    /// One line for the list: whitespace runs collapsed, cut at `length` characters
    static func preview(_ text: String, length: Int = 200) -> String {
        let collapsed = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        return collapsed.count > length ? String(collapsed.prefix(length - 1)) + "…" : collapsed
    }

    /// Text worth keeping: not blank, not too big
    static func shouldKeep(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf16.count <= maxTextLength
    }
}
