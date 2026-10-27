//
//  TodoSchedule.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Foundation

enum TodoBucket: Equatable {
    case overdue
    case today
    case upcoming
    case someday
}

/// Due dates of to-do items. Foundation only, so it can be tested without the app.
enum TodoSchedule {
    static func bucket(for due: Date?, now: Date, calendar: Calendar = .current) -> TodoBucket {
        guard let due else { return .someday }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: due)
        if day < today { return .overdue }
        if day == today { return .today }
        return .upcoming
    }

    /// "Today", "Tomorrow", "Yesterday", a weekday within the next week ("Fri"), otherwise "10 Nov"
    static func dueLabel(_ due: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...6: return format(due, "EEE", calendar: calendar, locale: locale)
        default: return format(due, "d MMM", calendar: calendar, locale: locale)
        }
    }

    private static func format(_ date: Date, _ pattern: String, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// Words that set a date when they end a task, in English and Indonesian, with the days they add
    private static let relativeWords: [String: Int] = [
        "today": 0, "hari ini": 0,
        "tomorrow": 1, "besok": 1,
        "lusa": 2,
        "next week": 7, "minggu depan": 7,
    ]

    /// Calendar weekday numbers: 1 is Sunday
    private static let weekdayWords: [String: Int] = [
        "sunday": 1, "sun": 1, "minggu": 1,
        "monday": 2, "mon": 2, "senin": 2,
        "tuesday": 3, "tue": 3, "tues": 3, "selasa": 3,
        "wednesday": 4, "wed": 4, "rabu": 4,
        "thursday": 5, "thu": 5, "thur": 5, "thurs": 5, "kamis": 5,
        "friday": 6, "fri": 6, "jumat": 6, "jum'at": 6,
        "saturday": 7, "sat": 7, "sabtu": 7,
    ]

    /// Splits a trailing date word off a task: "beli kopi besok" becomes "beli kopi", due tomorrow.
    /// Only the last word(s) count, and a task that is nothing but a date word keeps it as its title.
    /// A weekday means its next occurrence, so "tuesday" typed on a Tuesday is a week away.
    static func parseDue(_ text: String, now: Date, calendar: Calendar = .current) -> (title: String, due: Date?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let today = calendar.startOfDay(for: now)

        var candidates: [(word: String, days: Int)] = relativeWords.map { ($0.key, $0.value) }
        let todayWeekday = calendar.component(.weekday, from: today)
        for (word, weekday) in weekdayWords {
            let ahead = (weekday - todayWeekday + 7) % 7
            candidates.append((word, ahead == 0 ? 7 : ahead))
        }
        // Longer phrases first, so "minggu depan" wins over "minggu"
        candidates.sort { $0.word.count > $1.word.count }

        for candidate in candidates {
            guard let range = trimmed.range(of: " " + candidate.word, options: [.caseInsensitive, .anchored, .backwards]) else {
                continue
            }
            let title = trimmed[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            return (title, calendar.date(byAdding: .day, value: candidate.days, to: today))
        }
        return (trimmed, nil)
    }
}

/// When to remind about tasks still open today. Foundation only, so it can be tested without the app.
enum TodoReminderPlan {
    /// Hourly repeats stop at this hour so evenings stay quiet; the first reminder of the day still fires
    static let quietHour = 22
    static let repeatInterval: TimeInterval = 3600

    /// `reminderMinutes` is the time of day, in minutes after midnight
    static func shouldRemind(
        now: Date,
        reminderMinutes: Int,
        lastReminder: Date?,
        repeatHourly: Bool,
        openTasks: Int,
        calendar: Calendar = .current
    ) -> Bool {
        guard openTasks > 0,
              let reminderTime = calendar.date(byAdding: .minute, value: reminderMinutes, to: calendar.startOfDay(for: now)),
              now >= reminderTime
        else { return false }

        guard let lastReminder, lastReminder >= reminderTime else {
            // Nothing yet since today's reminder time, also when the Mac was asleep at that moment
            return true
        }
        return repeatHourly
            && now.timeIntervalSince(lastReminder) >= repeatInterval
            && calendar.component(.hour, from: now) < quietHour
    }

    /// "3 tasks still open today: a, b, c" or "5 tasks still open today: a, b, c and 2 more"
    static func message(openTitles: [String]) -> String {
        let count = openTitles.count
        let shown = openTitles.prefix(3).joined(separator: ", ")
        let more = count > 3 ? " and \(count - 3) more" : ""
        return "\(count) \(count == 1 ? "task" : "tasks") still open today: \(shown)\(more)"
    }
}
