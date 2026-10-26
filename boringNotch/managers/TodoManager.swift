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

    /// Open tasks in the order they were added, then finished tasks with the most recent first
    var sortedItems: [TodoItem] {
        let open = items.filter { !$0.isDone }.sorted { $0.createdAt < $1.createdAt }
        let done = items.filter(\.isDone).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        return open + done
    }

    var remainingCount: Int {
        items.filter { !$0.isDone }.count
    }

    var hasCompleted: Bool {
        items.contains(where: \.isDone)
    }

    func addDraft() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        items.append(TodoItem(title: title))
        draft = ""
    }

    func toggle(_ id: TodoItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isDone.toggle()
        items[index].completedAt = items[index].isDone ? Date() : nil
    }

    func delete(_ id: TodoItem.ID) {
        items.removeAll { $0.id == id }
    }

    func clearCompleted() {
        items.removeAll(where: \.isDone)
    }
}
