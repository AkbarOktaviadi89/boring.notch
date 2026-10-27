//
//  Notes.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Foundation

struct Note: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var isPinned = false
    var createdAt: Date
    var updatedAt: Date

    init(text: String = "", isPinned: Bool = false, createdAt: Date = Date()) {
        self.text = text
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var isBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Titles, previews, search and ordering for notes. Foundation only, so it can be tested without the app.
enum NoteText {
    static let untitled = "New note"
    static let maxTitleLength = 60

    private static func contentLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Markdown heading and list marks don't belong in a title or preview
    private static func stripMarks(_ line: String) -> String {
        var line = line
        for prefix in ["- [ ] ", "- [x] ", "- [X] "] where line.hasPrefix(prefix) {
            line.removeFirst(prefix.count)
        }
        while line.hasPrefix("#") { line.removeFirst() }
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("> ") { line.removeFirst(2) }
        return line.trimmingCharacters(in: .whitespaces)
    }

    /// The first non-empty line
    static func title(of text: String) -> String {
        guard let first = contentLines(text).first.map(stripMarks), !first.isEmpty else { return untitled }
        return first.count > maxTitleLength ? String(first.prefix(maxTitleLength - 1)) + "…" : first
    }

    /// The line after the title, for the list row
    static func preview(of text: String) -> String {
        contentLines(text).dropFirst().first.map(stripMarks) ?? ""
    }

    static func wordCount(of text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// Pinned first, then the most recently edited
    static func sorted(_ notes: [Note]) -> [Note] {
        notes.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    /// Every word of the query must appear somewhere in the note, ignoring case and accents
    static func matches(_ note: Note, query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        return words.allSatisfy { note.text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    static func search(_ notes: [Note], query: String) -> [Note] {
        sorted(notes.filter { matches($0, query: query) })
    }

    /// "14:05" today, "Yesterday", the weekday within a week, else "27 Oct"
    static func dateLabel(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days == 1 { return "Yesterday" }
        formatter.dateFormat = (1..<7).contains(days) ? "EEE" : "d MMM"
        return formatter.string(from: date)
    }}
