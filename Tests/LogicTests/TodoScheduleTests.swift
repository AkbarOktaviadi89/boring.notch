//
//  TodoScheduleTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Foundation

func runTodoScheduleTests() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
    let english = Locale(identifier: "en_US_POSIX")
    func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = english
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }
    let key = { (day: Date?) in day.map { StudyStats.dayKey($0, calendar: calendar) } ?? "nil" }
    // Tuesday afternoon
    let now = date("2026-10-27 15:00")

    // Buckets
    check("bucket no date", "\(TodoSchedule.bucket(for: nil, now: now, calendar: calendar))", "someday")
    check("bucket overdue", "\(TodoSchedule.bucket(for: date("2026-10-26 00:00"), now: now, calendar: calendar))", "overdue")
    check("bucket today", "\(TodoSchedule.bucket(for: date("2026-10-27 00:00"), now: now, calendar: calendar))", "today")
    check("bucket today later hour", "\(TodoSchedule.bucket(for: date("2026-10-27 23:30"), now: now, calendar: calendar))", "today")
    check("bucket upcoming", "\(TodoSchedule.bucket(for: date("2026-10-28 00:00"), now: now, calendar: calendar))", "upcoming")

    // Labels
    func label(_ text: String) -> String {
        TodoSchedule.dueLabel(date(text), now: now, calendar: calendar, locale: english)
    }
    check("label today", label("2026-10-27 00:00"), "Today")
    check("label tomorrow", label("2026-10-28 00:00"), "Tomorrow")
    check("label yesterday", label("2026-10-26 00:00"), "Yesterday")
    check("label weekday this week", label("2026-10-30 00:00"), "Fri")
    check("label far future", label("2026-11-10 00:00"), "10 Nov")
    check("label older past", label("2026-10-20 00:00"), "20 Oct")

    // Dates typed at the end of a task
    func parse(_ text: String) -> String {
        let parsed = TodoSchedule.parseDue(text, now: now, calendar: calendar)
        return "\(parsed.title)|\(key(parsed.due))"
    }
    check("parse besok", parse("beli kopi besok"), "beli kopi|2026-10-28")
    check("parse tomorrow", parse("Write tests tomorrow"), "Write tests|2026-10-28")
    check("parse hari ini any case", parse("call mom Hari Ini"), "call mom|2026-10-27")
    check("parse today", parse("ship it today"), "ship it|2026-10-27")
    check("parse lusa", parse("deploy lusa"), "deploy|2026-10-29")
    check("parse english weekday", parse("Review PR friday"), "Review PR|2026-10-30")
    check("parse short weekday", parse("gym fri"), "gym|2026-10-30")
    check("parse indonesian weekday", parse("bayar listrik jumat"), "bayar listrik|2026-10-30")
    check("parse jum'at", parse("bayar listrik jum'at"), "bayar listrik|2026-10-30")
    check("parse same weekday means next week", parse("standup tuesday"), "standup|2026-11-03")
    check("parse selasa next week", parse("standup selasa"), "standup|2026-11-03")
    check("parse minggu is sunday", parse("jogging minggu"), "jogging|2026-11-01")
    check("parse minggu depan", parse("liburan minggu depan"), "liburan|2026-11-03")
    check("parse next week", parse("plan trip next week"), "plan trip|2026-11-03")
    check("only trailing words count", parse("senin rapat tim"), "senin rapat tim|nil")
    check("word inside another word", parse("beli kerupuk sabtuan"), "beli kerupuk sabtuan|nil")
    check("date word alone stays a title", parse("besok"), "besok|nil")
    check("no date", parse("refactor parser"), "refactor parser|nil")
    check("trailing whitespace", parse("tidur cepat besok   "), "tidur cepat|2026-10-28")
}
