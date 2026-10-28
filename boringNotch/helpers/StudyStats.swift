//
//  StudyStats.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Foundation

enum PomodoroPhase: String, Codable, Equatable {
    case focus
    case shortBreak
    case longBreak

    var isBreak: Bool { self != .focus }
}

enum PomodoroPlan {
    /// What comes after a phase ends. `completedFocusSessions` already counts a focus session that just ended.
    static func next(after phase: PomodoroPhase, completedFocusSessions: Int, sessionsBeforeLongBreak: Int) -> PomodoroPhase {
        switch phase {
        case .focus:
            let every = max(1, sessionsBeforeLongBreak)
            return completedFocusSessions > 0 && completedFocusSessions.isMultiple(of: every) ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            return .focus
        }
    }
}

/// What the notch and the notification say when a phase ends
struct PhaseAnnouncement: Equatable {
    let ended: PomodoroPhase
    /// nil when Pomodoro is off and the timer just stops
    let next: PomodoroPhase?
    let nextMinutes: Int
    /// Focus sessions finished in this cycle, counting the one that just ended
    let completedInCycle: Int
    let sessionsBeforeLongBreak: Int
    /// Whether the next phase is already running
    let autoStarted: Bool

    /// Left of the closed notch: what starts now
    var phaseName: String {
        switch next {
        case nil: return "Done"
        case .focus: return "Focus"
        case .shortBreak: return "Break"
        case .longBreak: return "Long break"
        }
    }

    /// Right of the closed notch
    var detail: String {
        next == nil ? "Nice work" : "\(nextMinutes) min"
    }

    var title: String {
        switch next {
        case nil: return "Focus session done"
        case .focus: return "Break over, back to focus"
        case .shortBreak, .longBreak: return "Focus done, time for a break"
        }
    }

    var body: String {
        let every = max(1, sessionsBeforeLongBreak)
        let doneInRound = completedInCycle == 0 ? 0 : (completedInCycle - 1) % every + 1
        let phaseText: String
        switch next {
        case nil: return "Nice work. Start another session from the notch when you're ready."
        case .focus: phaseText = "Focus, \(nextMinutes) min"
        case .shortBreak: phaseText = "Short break, \(nextMinutes) min. \(doneInRound) of \(every) sessions done"
        case .longBreak: phaseText = "Long break, \(nextMinutes) min. You finished \(every) sessions"
        }
        return phaseText + (autoStarted ? " — already running." : ". Start it from the notch when you're ready.")
    }
}

struct StudyDay: Equatable {
    let date: Date
    let seconds: Int
}

/// Focused time per day, kept as "yyyy-MM-dd" -> seconds. Foundation only, so it can be tested without the app.
enum StudyStats {
    static let keepDays = 90

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Adds focused seconds to a day and drops days older than `keepDays`
    static func adding(_ seconds: Int, on date: Date, to log: [String: Int], calendar: Calendar = .current) -> [String: Int] {
        var log = log
        log[dayKey(date, calendar: calendar), default: 0] += max(0, seconds)
        if let cutoffDate = calendar.date(byAdding: .day, value: -keepDays, to: date) {
            // Keys sort like dates, so older days compare lower
            let cutoff = dayKey(cutoffDate, calendar: calendar)
            log = log.filter { $0.key >= cutoff }
        }
        return log
    }

    /// The last `count` days, oldest first, ending with `date`
    static func lastDays(_ count: Int, endingOn date: Date, log: [String: Int], calendar: Calendar = .current) -> [StudyDay] {
        let today = calendar.startOfDay(for: date)
        return (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return StudyDay(date: day, seconds: log[dayKey(day, calendar: calendar)] ?? 0)
        }
    }

    /// Consecutive days with at least `minimumSeconds` of focus, counting back from today,
    /// or from yesterday when nothing has been done yet today
    static func streak(endingOn date: Date, log: [String: Int], calendar: Calendar = .current, minimumSeconds: Int = 60) -> Int {
        var day = calendar.startOfDay(for: date)
        if (log[dayKey(day, calendar: calendar)] ?? 0) < minimumSeconds {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while (log[dayKey(day, calendar: calendar)] ?? 0) >= minimumSeconds {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// "1h 30m", "25m", "<1m", "0m"
    static func formatDuration(_ seconds: Int) -> String {
        if seconds <= 0 { return "0m" }
        if seconds < 60 { return "<1m" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
