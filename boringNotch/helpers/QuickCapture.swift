//
//  QuickCapture.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-28.
//

import Foundation

enum CaptureTarget: Equatable {
    case todo(title: String, due: Date?)
    case note(String)
}

/// Where a line typed into the quick-capture field goes. Foundation only, so it can be tested without the app.
enum QuickCapture {
    /// A note starts with one of these; anything else is a to-do
    static let notePrefixes = ["note:", "catatan:", "n:"]
    /// Optional, for a task that itself starts with "n:"
    static let todoPrefixes = ["todo:", "t:"]

    /// A task without a date word is due today, so it shows up in Today and in the daily reminder.
    /// Returns nil when there is nothing to save.
    static func parse(_ text: String, now: Date, calendar: Calendar = .current) -> CaptureTarget? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let body = strip(notePrefixes, from: trimmed) {
            return body.isEmpty ? nil : .note(body)
        }
        let task = strip(todoPrefixes, from: trimmed) ?? trimmed
        let parsed = TodoSchedule.parseDue(task, now: now, calendar: calendar)
        guard !parsed.title.isEmpty else { return nil }
        return .todo(title: parsed.title, due: parsed.due ?? calendar.startOfDay(for: now))
    }

    /// "To-do · Tomorrow", "To-do · Fri" or "Note", for the hint under the field and the confirmation
    static func destination(of target: CaptureTarget, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        switch target {
        case .note:
            return "Note"
        case .todo(_, let due?):
            return "To-do · " + TodoSchedule.dueLabel(due, now: now, calendar: calendar, locale: locale)
        case .todo(_, nil):
            return "To-do"
        }
    }

    private static func strip(_ prefixes: [String], from text: String) -> String? {
        for prefix in prefixes where text.lowercased().hasPrefix(prefix) {
            return String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
