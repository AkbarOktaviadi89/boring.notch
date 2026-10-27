//
//  TodoReminder.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import AppKit
import Combine
import Defaults
import UserNotifications

/// Reminds about tasks due today (or overdue) that are still open: a hint on the closed notch,
/// and optionally a macOS notification that stays in Notification Center.
@MainActor
final class TodoReminder: ObservableObject {
    static let shared = TodoReminder()

    /// Open tasks shown on the closed notch while a reminder is up
    @Published private(set) var activeCount: Int?

    static let visibleDuration: Duration = .seconds(15)

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var hideTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // Timers don't fire while the Mac sleeps; check as soon as it wakes up
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        check()
    }

    func check(now: Date = Date()) {
        guard Defaults[.todoEnabled], Defaults[.todoReminderEnabled] else { return }
        let open = openTasksToday(now: now)
        guard TodoReminderPlan.shouldRemind(
            now: now,
            reminderMinutes: Defaults[.todoReminderMinutes],
            lastReminder: Defaults[.todoReminderLastFired],
            repeatHourly: Defaults[.todoReminderRepeat],
            openTasks: open.count
        ) else { return }
        Defaults[.todoReminderLastFired] = now
        remind(about: open)
    }

    /// From the Settings button: shows the reminder now, even if nothing is open, without touching the schedule
    func showTest() {
        let open = openTasksToday(now: Date())
        remind(about: open.isEmpty ? [TodoItem(title: "Example task")] : open)
    }

    /// Opens the To-do tab on Today when the notch opens during a reminder. Returns false when there is none.
    @discardableResult
    func accept() -> Bool {
        guard activeCount != nil, Defaults[.todoEnabled] else { return false }
        Defaults[.todoFilter] = .today
        BoringViewCoordinator.shared.currentView = .todo
        dismiss()
        return true
    }

    func dismiss() {
        hideTask?.cancel()
        activeCount = nil
    }

    private func openTasksToday(now: Date) -> [TodoItem] {
        TodoManager.shared.items(in: .today, now: now).filter { !$0.isDone }
    }

    private func remind(about tasks: [TodoItem]) {
        activeCount = tasks.count
        NSSound(named: "Ping")?.play()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleDuration)
            guard !Task.isCancelled else { return }
            self?.activeCount = nil
        }
        if Defaults[.todoReminderSystemNotification] {
            postNotification(TodoReminderPlan.message(openTitles: tasks.map(\.title)))
        }
    }

    private func postNotification(_ body: String) {
        let center = UNUserNotificationCenter.current()
        // macOS asks for permission the first time only
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "To-do"
            content.body = body
            // The notch already plays a sound
            content.sound = nil
            // One identifier, so a repeat replaces the previous notification instead of piling up
            center.add(UNNotificationRequest(identifier: "todo-reminder", content: content, trigger: nil))
        }
    }
}
