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

    // Phase-change announcements
    func say(_ ended: PomodoroPhase, _ next: PomodoroPhase?, _ minutes: Int, done: Int, auto: Bool = true) -> PhaseAnnouncement {
        PhaseAnnouncement(ended: ended, next: next, nextMinutes: minutes, completedInCycle: done, sessionsBeforeLongBreak: 4, autoStarted: auto)
    }
    check("announce break label", say(.focus, .shortBreak, 5, done: 1).phaseName, "Break")
    check("announce long break label", say(.focus, .longBreak, 15, done: 4).phaseName, "Long break")
    check("announce focus label", say(.shortBreak, .focus, 25, done: 1).detail, "25 min")
    check("announce done label", say(.focus, nil, 0, done: 1).phaseName, "Done")
    check("announce done detail", say(.focus, nil, 0, done: 1).detail, "Nice work")
    check("announce break title", say(.focus, .shortBreak, 5, done: 1).title, "Focus done, time for a break")
    check("announce focus title", say(.shortBreak, .focus, 25, done: 1).title, "Break over, back to focus")
    check("announce break body", say(.focus, .shortBreak, 5, done: 2).body, "Short break, 5 min. 2 of 4 sessions done — already running.")
    check("announce body second round", say(.focus, .shortBreak, 5, done: 6).body, "Short break, 5 min. 2 of 4 sessions done — already running.")
    check("announce long break body", say(.focus, .longBreak, 15, done: 4).body, "Long break, 15 min. You finished 4 sessions — already running.")
    check("announce waits", say(.shortBreak, .focus, 25, done: 1, auto: false).body, "Focus, 25 min. Start it from the notch when you're ready.")
    contains("announce done body", say(.focus, nil, 0, done: 1).body, "Nice work")
}
