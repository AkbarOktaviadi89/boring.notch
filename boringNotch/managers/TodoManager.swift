//
//  TodoManager.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Combine
import Defaults
import Foundation

struct TodoItem: Codable, Identifiable, Equatable, Defaults.Serializable {
    var id = UUID()
    var title: String
    var isDone = false
    var createdAt = Date()
    var completedAt: Date?
    /// Start of the day the task is due. Optional, so tasks saved before due dates existed still decode.
    var dueDate: Date?
}

enum TodoFilter: String, CaseIterable, Identifiable, Defaults.Serializable {
    case today = "Today"
    case upcoming = "Upcoming"
    case all = "All"

    var id: Self { self }
}

@MainActor
final class TodoManager: ObservableObject {
    static let shared = TodoManager()

    @Published private(set) var items: [TodoItem] = Defaults[.todoItems] {
        didSet { Defaults[.todoItems] = items }
    }

    /// Text typed into the add field, kept when the notch closes mid-typing
    @Published var draft: String = ""

    private init() {}

    func bucket(of item: TodoItem, now: Date = Date()) -> TodoBucket {
        TodoSchedule.bucket(for: item.dueDate, now: now)
    }

    /// Open tasks first, then finished ones with the most recent first.
    /// Today: overdue, then today. Upcoming: by due date. All: dated tasks by date, then the rest as added.
    func items(in filter: TodoFilter, now: Date = Date()) -> [TodoItem] {
        let matching = items.filter { item in
            switch filter {
            case .today: return [.overdue, .today].contains(bucket(of: item, now: now))
            case .upcoming: return bucket(of: item, now: now) == .upcoming
            case .all: return true
            }
        }
        let open = matching.filter { !$0.isDone }.sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case let (l?, r?) where l != r: return l < r
            case (.some, .none): return true
            case (.none, .some): return false
            default: return lhs.createdAt < rhs.createdAt
            }
        }
        let done = matching.filter(\.isDone).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        return open + done
    }

    func openCount(in filter: TodoFilter, now: Date = Date()) -> Int {
        items(in: filter, now: now).filter { !$0.isDone }.count
    }

    var hasOverdue: Bool {
        items.contains { !$0.isDone && bucket(of: $0) == .overdue }
    }

    var remainingCount: Int {
        items.filter { !$0.isDone }.count
    }

    var hasCompleted: Bool {
        items.contains(where: \.isDone)
    }

    /// The due date a new task gets when its text doesn't name one
    static func defaultDue(for filter: TodoFilter, now: Date = Date()) -> Date? {
        let today = Calendar.current.startOfDay(for: now)
        switch filter {
        case .today: return today
        case .upcoming: return Calendar.current.date(byAdding: .day, value: 1, to: today)
        case .all: return nil
        }
    }

    /// Returns the new task, so the view can say where it went when it lands outside the current filter
    @discardableResult
    func addDraft(in filter: TodoFilter) -> TodoItem? {
        let parsed = TodoSchedule.parseDue(draft, now: Date())
        guard !parsed.title.isEmpty else { return nil }
        let item = add(title: parsed.title, due: parsed.due ?? Self.defaultDue(for: filter))
        draft = ""
        return item
    }

    @discardableResult
    func add(title: String, due: Date?) -> TodoItem {
        let item = TodoItem(title: title, dueDate: due)
        items.append(item)
        return item
    }

    func item(with id: TodoItem.ID) -> TodoItem? {
        items.first { $0.id == id }
    }

    func toggle(_ id: TodoItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isDone.toggle()
        items[index].completedAt = items[index].isDone ? Date() : nil
    }

    /// Days from today, or nil to remove the due date
    func setDue(_ id: TodoItem.ID, daysFromToday: Int?) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let today = Calendar.current.startOfDay(for: Date())
        items[index].dueDate = daysFromToday.flatMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    func moveOverdueToToday() {
        let today = Calendar.current.startOfDay(for: Date())
        for index in items.indices where !items[index].isDone && bucket(of: items[index]) == .overdue {
            items[index].dueDate = today
        }
    }

    func delete(_ id: TodoItem.ID) {
        items.removeAll { $0.id == id }
    }

    func clearCompleted() {
        items.removeAll(where: \.isDone)
    }
}
