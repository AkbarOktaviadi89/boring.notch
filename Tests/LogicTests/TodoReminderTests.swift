//
//  TodoReminderTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Foundation

func runTodoReminderTests() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
    func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }
    let fourPM = 16 * 60
    func remind(_ now: String, last: String? = nil, repeatHourly: Bool = false, open: Int = 2) -> String {
        String(TodoReminderPlan.shouldRemind(
            now: date(now), reminderMinutes: fourPM, lastReminder: last.map(date),
            repeatHourly: repeatHourly, openTasks: open, calendar: calendar
        ))
    }

    check("before the reminder time", remind("2026-10-27 15:59"), "false")
    check("at the reminder time", remind("2026-10-27 16:00"), "true")
    check("catches up after sleep", remind("2026-10-27 19:30"), "true")
    check("nothing open", remind("2026-10-27 16:30", open: 0), "false")
    check("already reminded today", remind("2026-10-27 18:00", last: "2026-10-27 16:00"), "false")
    check("reminded yesterday only", remind("2026-10-27 16:05", last: "2026-10-26 16:00"), "true")
    check("reminder before today's time doesn't count", remind("2026-10-27 16:05", last: "2026-10-27 09:00"), "true")
    check("hourly repeat after an hour", remind("2026-10-27 17:00", last: "2026-10-27 16:00", repeatHourly: true), "true")
    check("hourly repeat too soon", remind("2026-10-27 16:59", last: "2026-10-27 16:00", repeatHourly: true), "false")
    check("hourly repeat stops at 22:00", remind("2026-10-27 22:10", last: "2026-10-27 21:00", repeatHourly: true), "false")
    check("hourly repeat until 22:00", remind("2026-10-27 21:59", last: "2026-10-27 20:30", repeatHourly: true), "true")
    check("late reminder time still fires once", String(TodoReminderPlan.shouldRemind(
        now: date("2026-10-27 23:00"), reminderMinutes: 22 * 60 + 30, lastReminder: nil,
        repeatHourly: true, openTasks: 1, calendar: calendar
    )), "true")

    check("message one task", TodoReminderPlan.message(openTitles: ["Write tests"]), "1 task still open today: Write tests")
    check("message lists up to three", TodoReminderPlan.message(openTitles: ["a", "b", "c", "d", "e"]), "5 tasks still open today: a, b, c and 2 more")
    check("message three", TodoReminderPlan.message(openTitles: ["a", "b", "c"]), "3 tasks still open today: a, b, c")
}
