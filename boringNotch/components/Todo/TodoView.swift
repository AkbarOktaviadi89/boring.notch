//
//  TodoView.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Defaults
import SwiftUI

struct TodoView: View {
    @ObservedObject var todo = TodoManager.shared
    @Default(.todoFilter) var filter
    @FocusState private var isFieldFocused: Bool
    /// "Added for Tomorrow" when a new task lands outside the current filter
    @State private var addedNote: String?
    @State private var noteTask: Task<Void, Never>?

    var body: some View {
        // Re-render every minute so "Today" moves on at midnight while the tab stays open
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 6) {
                filterRow(now: context.date)
                addField
                list(todo.items(in: filter, now: context.date), now: context.date)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .acceptsNotchKeyboardInput()
    }

    // MARK: - Header

    private func filterRow(now: Date) -> some View {
        HStack(spacing: 8) {
            CapsuleSegmentedPicker(options: TodoFilter.allCases, selection: $filter) { option in
                let count = todo.openCount(in: option, now: now)
                return option != .all && count > 0 ? "\(option.rawValue) \(count)" : option.rawValue
            }

            if let addedNote {
                Text(addedNote)
                    .font(.caption)
                    .foregroundStyle(Color.effectiveAccent)
                    .transition(.opacity)
            }

            Spacer()

            if todo.hasOverdue && filter != .upcoming {
                smallButton("Move overdue to today") {
                    withAnimation(.smooth) { todo.moveOverdueToToday() }
                }
                .foregroundStyle(.red.opacity(0.9))
            }
            if todo.hasCompleted {
                smallButton("Clear done") {
                    withAnimation(.smooth) { todo.clearCompleted() }
                }
                .foregroundStyle(.gray)
            }
        }
    }

    private var addField: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(Color.effectiveAccent)
            TextField(placeholder, text: $todo.draft)
                .textFieldStyle(.plain)
                .focused($isFieldFocused)
                .onSubmit(add)
                .onExitCommand {
                    isFieldFocused = false
                    NotchKeyboardFocus.returnKeyboard()
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color(nsColor: .secondarySystemFill)))
    }

    private var placeholder: LocalizedStringKey {
        switch filter {
        case .today: return "Add for today, or end with besok, friday, next week…"
        case .upcoming: return "Add for tomorrow, or end with lusa, senin, next week…"
        case .all: return "Add a task; end with today, besok, friday… to set a date"
        }
    }

    private func add() {
        guard let item = todo.addDraft(in: filter) else { return }
        // Say where the task went if the current filter doesn't show it
        let visibleHere = todo.items(in: filter).contains { $0.id == item.id }
        guard !visibleHere, let due = item.dueDate else { return }
        withAnimation(.smooth) { addedNote = "Added for \(TodoSchedule.dueLabel(due, now: Date()))" }
        noteTask?.cancel()
        noteTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth) { addedNote = nil }
        }
    }

    private func smallButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption)
            .buttonStyle(PlainButtonStyle())
    }

    // MARK: - List

    @ViewBuilder
    private func list(_ items: [TodoItem], now: Date) -> some View {
        if items.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: filter == .today ? "sun.max" : "checklist")
                    .font(.title2)
                Text(emptyText)
                    .font(.callout)
            }
            .foregroundStyle(.gray)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(items) { item in
                        TodoRow(item: item, bucket: todo.bucket(of: item, now: now), now: now, filter: filter)
                    }
                }
                .animation(.smooth, value: items)
            }
            .allowsScrollingInOpenNotch()
        }
    }

    private var emptyText: LocalizedStringKey {
        switch filter {
        case .today: return "Nothing due today"
        case .upcoming: return "Nothing coming up"
        case .all: return "No tasks yet"
        }
    }
}

private struct TodoRow: View {
    let item: TodoItem
    let bucket: TodoBucket
    let now: Date
    let filter: TodoFilter
    @State private var isHovering = false

    /// In Today, tasks due today don't need a chip saying so
    private var showsDueChip: Bool {
        guard item.dueDate != nil else { return false }
        return !(filter == .today && bucket == .today)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.smooth) { TodoManager.shared.toggle(item.id) }
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(item.isDone ? Color.effectiveAccent : .gray)
            }
            .buttonStyle(PlainButtonStyle())

            Text(item.title)
                .font(.callout)
                .strikethrough(item.isDone)
                .foregroundStyle(item.isDone ? .gray : .white)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            if showsDueChip, let due = item.dueDate {
                Text(TodoSchedule.dueLabel(due, now: now))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(chipColor.opacity(0.18)))
                    .foregroundStyle(chipColor)
                    .opacity(item.isDone ? 0.5 : 1)
            }

            if !item.isDone && Defaults[.focusTimerEnabled] {
                Button(action: focusOnTask) {
                    Image(systemName: "timer")
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                }
                .buttonStyle(PlainButtonStyle())
                .opacity(isHovering ? 1 : 0)
                .help("Focus on this task")
            }

            Button {
                withAnimation(.smooth) { TodoManager.shared.delete(item.id) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
            }
            .buttonStyle(PlainButtonStyle())
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.white.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Due today") { setDue(0) }
            Button("Due tomorrow") { setDue(1) }
            Button("Due next week") { setDue(7) }
            Button("No due date") { setDue(nil) }
            if !item.isDone && Defaults[.focusTimerEnabled] {
                Divider()
                Button("Focus on this", action: focusOnTask)
            }
            Divider()
            Button("Delete") {
                withAnimation(.smooth) { TodoManager.shared.delete(item.id) }
            }
        }
    }

    private var chipColor: Color {
        switch bucket {
        case .overdue: return .red
        case .today: return .effectiveAccent
        case .upcoming, .someday: return .gray
        }
    }

    /// Points the timer at this task and opens it, ready to start
    private func focusOnTask() {
        FocusTimerManager.shared.taskID = item.id
        Defaults[.focusSection] = .timer
        withAnimation(.smooth) { BoringViewCoordinator.shared.currentView = .focus }
    }

    private func setDue(_ days: Int?) {
        withAnimation(.smooth) { TodoManager.shared.setDue(item.id, daysFromToday: days) }
    }
}

#Preview {
    TodoView()
        .environmentObject(BoringViewModel())
        .frame(width: 600, height: 150)
        .background(.black)
}

/// Shown on the closed notch for a few seconds when tasks due today are still open.
/// Opening the notch while it shows opens the To-do tab on Today.
struct TodoReminderLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    let count: Int

    var body: some View {
        let sideWidth = FocusLiveActivity.sideWidth(notchHeight: vm.effectiveClosedNotchHeight)

        HStack {
            Image(systemName: "checklist")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: sideWidth)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + -cornerRadiusInsets.closed.top)

            Text("\(count) left")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: sideWidth)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .help("Tasks due today are still open. Open the notch to see them.")
    }
}
