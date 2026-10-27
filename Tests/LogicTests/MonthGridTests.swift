//
//  MonthGridTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Foundation

func runMonthGridTests() {
    func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        calendar.firstWeekday = firstWeekday
        return calendar
    }
    let sunday = calendar(firstWeekday: 1)
    let monday = calendar(firstWeekday: 2)
    func date(_ text: String, _ calendar: Calendar) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }
    let key = { (day: Date, calendar: Calendar) in StudyStats.dayKey(day, calendar: calendar) }

    // October 2026 starts on a Thursday
    let october = MonthGrid.days(forMonthContaining: date("2026-10-15 12:00", sunday), calendar: sunday)
    check("grid has 6 weeks", String(october.count), "42")
    check("sunday-first grid start", october.first.map { key($0, sunday) }, "2026-09-27")
    check("sunday-first grid end", october.last.map { key($0, sunday) }, "2026-11-07")
    let octoberMonday = MonthGrid.days(forMonthContaining: date("2026-10-15 12:00", monday), calendar: monday)
    check("monday-first grid start", octoberMonday.first.map { key($0, monday) }, "2026-09-28")
    // February 2026 starts on a Sunday: the grid starts on the 1st itself
    let february = MonthGrid.days(forMonthContaining: date("2026-02-10 08:00", sunday), calendar: sunday)
    check("month starting on first weekday", february.first.map { key($0, sunday) }, "2026-02-01")
    check("days are start of day", String(Calendar.current.dateComponents(in: sunday.timeZone, from: october[10]).hour ?? -1), "0")

    let symbols = ["S", "M", "T", "W", "T", "F", "S"]
    check("weekday symbols sunday-first", MonthGrid.weekdaySymbols(symbols, firstWeekday: 1).joined(), "SMTWTFS")
    check("weekday symbols monday-first", MonthGrid.weekdaySymbols(symbols, firstWeekday: 2).joined(), "MTWTFSS")

    // Days that have events
    let events: [(start: Date, end: Date, isAllDay: Bool)] = [
        (date("2026-10-05 10:00", sunday), date("2026-10-05 11:00", sunday), false),
        (date("2026-10-09 22:00", sunday), date("2026-10-11 01:00", sunday), false),
        (date("2026-10-20 00:00", sunday), date("2026-10-21 00:00", sunday), true),
        (date("2026-10-24 23:00", sunday), date("2026-10-25 00:00", sunday), false),
        (date("2026-10-30 09:00", sunday), date("2026-10-30 09:00", sunday), false),
    ]
    let days = MonthGrid.eventDayKeys(events, calendar: sunday)
    check("event day keys", days.sorted().joined(separator: ","), "2026-10-05,2026-10-09,2026-10-10,2026-10-11,2026-10-20,2026-10-24,2026-10-30")
}
