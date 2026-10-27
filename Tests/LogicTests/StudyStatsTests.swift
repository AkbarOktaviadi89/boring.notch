//
//  StudyStatsTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Foundation

func runStudyStatsTests() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    func day(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }
    let today = day("2026-10-27 15:30")

    var log = StudyStats.adding(1500, on: today, to: [:], calendar: calendar)
    check("study add", log["2026-10-27"].map(String.init), "1500")
    log = StudyStats.adding(600, on: today, to: log, calendar: calendar)
    check("study add accumulates", log["2026-10-27"].map(String.init), "2100")
    let pruned = StudyStats.adding(60, on: today, to: ["2026-07-01": 999, "2026-10-01": 5], calendar: calendar)
    check("study prunes days older than 90", pruned["2026-07-01"].map(String.init) ?? "nil", "nil")
    check("study keeps recent days", pruned["2026-10-01"].map(String.init), "5")

    let week = StudyStats.lastDays(7, endingOn: today, log: ["2026-10-21": 60, "2026-10-27": 2100, "2026-10-20": 999], calendar: calendar)
    check("last 7 days count", String(week.count), "7")
    check("last 7 days first", week.first.map { StudyStats.dayKey($0.date, calendar: calendar) }, "2026-10-21")
    check("last 7 days seconds", week.map { String($0.seconds) }.joined(separator: ","), "60,0,0,0,0,0,2100")

    let streakLog = ["2026-10-27": 1500, "2026-10-26": 60, "2026-10-25": 30, "2026-10-24": 3000]
    check("streak stops at a day under a minute", String(StudyStats.streak(endingOn: today, log: streakLog, calendar: calendar)), "2")
    check("streak can start yesterday", String(StudyStats.streak(endingOn: today, log: ["2026-10-26": 600, "2026-10-25": 600], calendar: calendar)), "2")
    check("no streak", String(StudyStats.streak(endingOn: today, log: ["2026-10-24": 600], calendar: calendar)), "0")

    check("duration hours", StudyStats.formatDuration(5400), "1h 30m")
    check("duration minutes", StudyStats.formatDuration(1500), "25m")
    check("duration under a minute", StudyStats.formatDuration(59), "<1m")
    check("duration zero", StudyStats.formatDuration(0), "0m")

    check("pomodoro short break", "\(PomodoroPlan.next(after: .focus, completedFocusSessions: 1, sessionsBeforeLongBreak: 4))", "shortBreak")
    check("pomodoro long break", "\(PomodoroPlan.next(after: .focus, completedFocusSessions: 4, sessionsBeforeLongBreak: 4))", "longBreak")
    check("pomodoro long break again at 8", "\(PomodoroPlan.next(after: .focus, completedFocusSessions: 8, sessionsBeforeLongBreak: 4))", "longBreak")
    check("pomodoro after short break", "\(PomodoroPlan.next(after: .shortBreak, completedFocusSessions: 1, sessionsBeforeLongBreak: 4))", "focus")
    check("pomodoro after long break", "\(PomodoroPlan.next(after: .longBreak, completedFocusSessions: 4, sessionsBeforeLongBreak: 4))", "focus")
}
