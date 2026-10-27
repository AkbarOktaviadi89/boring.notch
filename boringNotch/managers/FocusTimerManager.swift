//
//  FocusTimerManager.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import AppKit
import Combine
import Defaults

@MainActor
final class FocusTimerManager: ObservableObject {
    static let shared = FocusTimerManager()

    enum State: Equatable {
        case idle
        case running
        case paused
        case finished
    }

    static let minDuration = 1
    static let maxDuration = 180
    static let presets = [15, 25, 45, 60]
    /// Focus shorter than this when a session is reset doesn't count as study time
    static let minimumRecordedSeconds = 60

    @Published private(set) var state: State = .idle
    @Published private(set) var phase: PomodoroPhase = .focus
    @Published private(set) var remaining: TimeInterval
    @Published private(set) var sessionDuration: TimeInterval
    @Published private(set) var completedToday: Int = 0
    /// Focus sessions finished since the Pomodoro cycle started
    @Published private(set) var completedInCycle: Int = 0
    /// "yyyy-MM-dd" -> focused seconds, for the Stats section
    @Published private(set) var studyLog: [String: Int] = Defaults[.studySecondsByDay]

    private var endDate: Date?
    private var timer: Timer?
    private var finishedDismissTask: Task<Void, Never>?

    private init() {
        let duration = TimeInterval(Defaults[.focusTimerDuration] * 60)
        sessionDuration = duration
        remaining = duration
        completedToday = Calendar.current.isDateInToday(Defaults[.focusCompletedDate])
            ? Defaults[.focusCompletedCount] : 0
    }

    // MARK: - Derived state

    var isActive: Bool {
        state == .running || state == .paused
    }

    /// 0 when the session starts, 1 when it ends.
    var progress: Double {
        guard sessionDuration > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / sessionDuration))
    }

    var remainingText: String {
        Self.format(remaining)
    }

    static func format(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval.rounded(.up))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func duration(of phase: PomodoroPhase) -> TimeInterval {
        let minutes: Int
        switch phase {
        case .focus: minutes = Defaults[.focusTimerDuration]
        case .shortBreak: minutes = Defaults[.pomodoroShortBreak]
        case .longBreak: minutes = Defaults[.pomodoroLongBreak]
        }
        return TimeInterval(max(1, minutes) * 60)
    }

    // MARK: - Controls

    /// Changes the focus length. Ignored while a session is running or paused.
    func setDuration(minutes: Int) {
        guard !isActive else { return }
        let clamped = min(Self.maxDuration, max(Self.minDuration, minutes))
        Defaults[.focusTimerDuration] = clamped
        finishedDismissTask?.cancel()
        state = .idle
        if phase == .focus {
            sessionDuration = TimeInterval(clamped * 60)
            remaining = sessionDuration
        }
    }

    func start() {
        switch state {
        case .running:
            return
        case .paused:
            break
        case .idle, .finished:
            finishedDismissTask?.cancel()
            sessionDuration = Self.duration(of: phase)
            remaining = sessionDuration
        }
        endDate = Date().addingTimeInterval(remaining)
        state = .running
        startTicking()
    }

    func pause() {
        guard state == .running else { return }
        tick()
        stopTicking()
        endDate = nil
        state = .paused
    }

    func toggle() {
        state == .running ? pause() : start()
    }

    /// Stops everything and starts the Pomodoro cycle over. Focus time already spent is still counted.
    func reset() {
        if isActive {
            tick()
            if phase == .focus {
                recordFocus(seconds: Int(sessionDuration - remaining), minimum: Self.minimumRecordedSeconds)
            }
        }
        stopTicking()
        finishedDismissTask?.cancel()
        endDate = nil
        state = .idle
        phase = .focus
        completedInCycle = 0
        sessionDuration = Self.duration(of: .focus)
        remaining = sessionDuration
    }

    /// Ends a break early and moves on to the next focus session
    func skipBreak() {
        guard phase.isBreak else { return }
        stopTicking()
        finishedDismissTask?.cancel()
        endDate = nil
        state = .idle
        phase = .focus
        sessionDuration = Self.duration(of: .focus)
        remaining = sessionDuration
        if Defaults[.pomodoroAutoStart] { start() }
    }

    // MARK: - Ticking

    private func startTicking() {
        stopTicking()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        // .common keeps the timer firing while menus or the settings window are being interacted with
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard state == .running, let endDate else { return }
        // Computed from the end date so sleep or a busy main thread never makes the timer drift
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 {
            finish()
        }
    }

    private func finish() {
        stopTicking()
        endDate = nil
        remaining = 0
        let ended = phase

        if ended == .focus {
            recordFocus(seconds: Int(sessionDuration), minimum: 0)
            recordCompletedSession()
            completedInCycle += 1
        }
        if Defaults[.focusTimerSound] {
            // A different sound when a break ends, so it's clear what starts next
            NSSound(named: ended == .focus ? "Glass" : "Hero")?.play()
        }

        guard Defaults[.pomodoroEnabled] else {
            state = .finished
            // Keep the "done" state visible for a while, then go back to idle
            scheduleDismiss { $0.reset() }
            return
        }

        phase = PomodoroPlan.next(
            after: ended,
            completedFocusSessions: completedInCycle,
            sessionsBeforeLongBreak: Defaults[.pomodoroSessionsBeforeLongBreak]
        )
        sessionDuration = Self.duration(of: phase)
        remaining = sessionDuration
        if Defaults[.pomodoroAutoStart] {
            state = .idle
            start()
        } else {
            // Shows "Done" briefly, then waits with the next phase ready to start
            state = .finished
            scheduleDismiss { $0.state = .idle }
        }
    }

    private func scheduleDismiss(_ action: @escaping (FocusTimerManager) -> Void) {
        finishedDismissTask?.cancel()
        finishedDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self else { return }
            action(self)
        }
    }

    private func recordFocus(seconds: Int, minimum: Int) {
        guard seconds > 0, seconds >= minimum else { return }
        studyLog = StudyStats.adding(seconds, on: Date(), to: Defaults[.studySecondsByDay])
        Defaults[.studySecondsByDay] = studyLog
    }

    private func recordCompletedSession() {
        if Calendar.current.isDateInToday(Defaults[.focusCompletedDate]) {
            Defaults[.focusCompletedCount] += 1
        } else {
            Defaults[.focusCompletedCount] = 1
        }
        Defaults[.focusCompletedDate] = Date()
        completedToday = Defaults[.focusCompletedCount]
    }
}
