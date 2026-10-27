//
//  MonthGrid.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Foundation

/// Dates behind the month view of the calendar. Foundation only, so it can be tested without the app.
enum MonthGrid {
    /// Always six weeks, so the grid keeps its height from month to month
    static let dayCount = 42

    /// Start of each day shown for the month: the first row starts on the calendar's first weekday
    static func days(forMonthContaining date: Date, calendar: Calendar = .current) -> [Date] {
        guard let monthStart = calendar.dateInterval(of: .month, for: date)?.start else { return [] }
        let weekday = calendar.component(.weekday, from: monthStart)
        let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: monthStart) else { return [] }
        return (0..<dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    /// `symbols` start on Sunday, like Calendar.veryShortWeekdaySymbols
    static func weekdaySymbols(_ symbols: [String], firstWeekday: Int) -> [String] {
        guard !symbols.isEmpty else { return [] }
        let shift = (firstWeekday - 1) % symbols.count
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// Day keys ("yyyy-MM-dd") of every day an event touches. The end is exclusive,
    /// so an event ending at midnight (like an all-day event) doesn't spill into the next day.
    static func eventDayKeys(_ events: [(start: Date, end: Date, isAllDay: Bool)], calendar: Calendar = .current) -> Set<String> {
        var keys = Set<String>()
        for event in events {
            let lastMoment = event.end > event.start ? event.end.addingTimeInterval(-1) : event.start
            var day = calendar.startOfDay(for: event.start)
            var guardDays = 0
            while day <= lastMoment, guardDays < 366 {
                keys.insert(StudyStats.dayKey(day, calendar: calendar))
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
                guardDays += 1
            }
        }
        return keys
    }
}
