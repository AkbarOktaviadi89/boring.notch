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

    @Published private(set) var state: State = .idle
    @Published private(set) var remaining: TimeInterval
    @Published private(set) var sessionDuration: TimeInterval
    @Published private(set) var completedToday: Int = 0

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

    // MARK: - Controls

    /// Changes the session length. Ignored while a session is running or paused.
    func setDuration(minutes: Int) {
        guard !isActive else { return }
        let clamped = min(Self.maxDuration, max(Self.minDuration, minutes))
        Defaults[.focusTimerDuration] = clamped
        finishedDismissTask?.cancel()
        state = .idle
        sessionDuration = TimeInterval(clamped * 60)
        remaining = sessionDuration
    }

    func start() {
        switch state {
        case .running:
            return
        case .paused:
            break
        case .idle, .finished:
            finishedDismissTask?.cancel()
            sessionDuration = TimeInterval(Defaults[.focusTimerDuration] * 60)
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

    func reset() {
        stopTicking()
        finishedDismissTask?.cancel()
        endDate = nil
        state = .idle
        sessionDuration = TimeInterval(Defaults[.focusTimerDuration] * 60)
        remaining = sessionDuration
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
        state = .finished
        recordCompletedSession()

        if Defaults[.focusTimerSound] {
            NSSound(named: "Glass")?.play()
        }

        // Keep the "done" state visible for a while, then go back to idle
        finishedDismissTask?.cancel()
        finishedDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            self?.reset()
        }
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
