//
//  FocusTimerView.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Defaults
import SwiftUI

enum FocusSection: String, CaseIterable, Identifiable, Defaults.Serializable {
    case timer = "Timer"
    case stats = "Stats"
    case cards = "Cards"

    var id: Self { self }
}

/// The Focus tab: the timer, study stats and flashcards, all about studying
struct FocusTabView: View {
    @Default(.focusSection) var section

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch section {
            case .timer: FocusTimerView()
            case .stats: FocusStatsView()
            case .cards: FlashcardsView()
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct FocusSectionPicker: View {
    @Default(.focusSection) var section

    var body: some View {
        CapsuleSegmentedPicker(options: FocusSection.allCases, selection: $section, title: \.rawValue)
    }
}

struct FocusTimerView: View {
    @ObservedObject var focus = FocusTimerManager.shared
    // The chosen task's title and done state live here
    @ObservedObject var todo = TodoManager.shared
    @Default(.focusTimerDuration) var duration
    @Default(.pomodoroEnabled) var pomodoroEnabled
    @Default(.pomodoroSessionsBeforeLongBreak) var sessionsBeforeLongBreak

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                FocusSectionPicker()
                FocusTaskPicker()
                Spacer()
                if pomodoroEnabled {
                    cycleDots
                }
                Text("\(focus.completedToday) today")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            HStack(spacing: 20) {
                FocusProgressRing(progress: focus.progress, state: focus.state, lineWidth: 7, isBreak: focus.phase.isBreak)
                    .overlay {
                        VStack(spacing: 1) {
                            Text(focus.state == .finished ? "Done" : focus.remainingText)
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText(countsDown: true))
                                .animation(.smooth, value: focus.remainingText)
                            Text(statusText)
                                .font(.caption2)
                                .foregroundStyle(.gray)
                        }
                    }
                    .frame(width: 100, height: 100)

                VStack(alignment: .leading, spacing: 12) {
                    durationPicker
                        .disabled(focus.isActive)
                        .opacity(focus.isActive ? 0.4 : 1)

                    controls
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// One dot per focus session before the long break
    private var cycleDots: some View {
        let total = max(1, sessionsBeforeLongBreak)
        let filled = focus.phase == .longBreak ? total : focus.completedInCycle % total
        return HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < filled ? Color.effectiveAccent : Color.white.opacity(0.15))
                    .frame(width: 6, height: 6)
            }
        }
        .help("Focus sessions in this Pomodoro cycle")
    }

    private var statusText: LocalizedStringKey {
        switch (focus.state, focus.phase) {
        case (.finished, .focus): return "Session complete"
        case (.finished, _): return "Break's up"
        case (.paused, _): return "Paused"
        case (.running, .focus): return "Focusing"
        case (.running, .shortBreak): return "Short break"
        case (.running, .longBreak): return "Long break"
        case (.idle, .focus): return "Ready"
        case (.idle, _): return "Break next"
        }
    }

    private var durationPicker: some View {
        HStack(spacing: 6) {
            ForEach(FocusTimerManager.presets, id: \.self) { minutes in
                Button {
                    focus.setDuration(minutes: minutes)
                } label: {
                    Text("\(minutes)m")
                        .font(.system(.callout, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(
                                duration == minutes
                                    ? Color.effectiveAccent.opacity(0.35)
                                    : Color(nsColor: .secondarySystemFill)
                            )
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                stepButton(icon: "minus") {
                    focus.setDuration(minutes: duration - step(down: true))
                }
                Text("\(duration) min")
                    .font(.system(.callout, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 52)
                stepButton(icon: "plus") {
                    focus.setDuration(minutes: duration + step(down: false))
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                focus.toggle()
            } label: {
                Label(primaryLabel, systemImage: focus.state == .running ? "pause.fill" : "play.fill")
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.effectiveAccent))
                    .foregroundStyle(.white)
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                focus.reset()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(.system(.callout, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(nsColor: .secondarySystemFill)))
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(focus.state == .idle && focus.phase == .focus && focus.completedInCycle == 0)
            .opacity(focus.state == .idle && focus.phase == .focus && focus.completedInCycle == 0 ? 0.4 : 1)

            // Right after a focus session is the natural moment to tick the task off
            if focus.task != nil && (focus.phase.isBreak || focus.state == .finished) {
                Button {
                    withAnimation(.smooth) { focus.completeTask() }
                } label: {
                    Label("Mark done", systemImage: "checkmark.circle")
                        .font(.system(.callout, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.green.opacity(0.3)))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Tick the task off in To-do")
            }

            if focus.phase.isBreak {
                Button {
                    focus.skipBreak()
                } label: {
                    Label("Skip", systemImage: "forward.end.fill")
                        .font(.system(.callout, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(nsColor: .secondarySystemFill)))
                }
                .buttonStyle(PlainButtonStyle())
                .help("End the break and start the next focus session")
            }
        }
    }

    private var primaryLabel: LocalizedStringKey {
        switch focus.state {
        case .running: return "Pause"
        case .paused: return "Resume"
        case .idle, .finished: return focus.phase.isBreak ? "Start break" : "Start"
        }
    }

    /// 1-minute steps for short sessions, 5-minute steps otherwise
    private func step(down: Bool) -> Int {
        (down ? duration <= 5 : duration < 5) ? 1 : 5
    }

    private func stepButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color(nsColor: .secondarySystemFill)))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Which to-do the timer is working on, picked from the open tasks
struct FocusTaskPicker: View {
    @ObservedObject var focus = FocusTimerManager.shared
    @ObservedObject var todo = TodoManager.shared

    var body: some View {
        let today = todo.items(in: .today).filter { !$0.isDone }
        let later = todo.items(in: .all).filter { item in !item.isDone && !today.contains { $0.id == item.id } }

        Menu {
            if today.isEmpty && later.isEmpty {
                Text("No open tasks in To-do")
            }
            if !today.isEmpty {
                Section("Today") {
                    ForEach(today) { item in taskButton(item) }
                }
            }
            if !later.isEmpty {
                Section("Later") {
                    ForEach(later) { item in taskButton(item) }
                }
            }
            if focus.task != nil {
                Divider()
                Button("No task") { focus.taskID = nil }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: focus.task == nil ? "scope" : "target")
                Text(focus.task?.title ?? "Pick a task")
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .font(.caption)
        .foregroundStyle(focus.task == nil ? .gray : .white)
        .frame(maxWidth: 170, alignment: .leading)
        .fixedSize(horizontal: focus.task == nil, vertical: false)
        .help("Focus time is also counted for the chosen task")
    }

    private func taskButton(_ item: TodoItem) -> some View {
        Button {
            focus.taskID = item.id
        } label: {
            if item.id == focus.taskID {
                Label(item.title, systemImage: "checkmark")
            } else {
                Text(item.title)
            }
        }
    }
}

struct FocusProgressRing: View {
    let progress: Double
    let state: FocusTimerManager.State
    let lineWidth: CGFloat
    var isBreak = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: state == .finished ? 1 : 1 - progress)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: progress)
        }
        .padding(lineWidth / 2)
    }

    private var ringColor: Color {
        switch state {
        case .finished: return .green
        case .paused: return .gray
        case .idle, .running: return isBreak ? .mint : .effectiveAccent
        }
    }
}

/// Shown on the closed notch while a focus session is running, paused or just finished
struct FocusLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var focus = FocusTimerManager.shared
    @ObservedObject var todo = TodoManager.shared

    /// Wide enough for a short task title next to the ring
    static let taskSideWidth: CGFloat = 104

    static func sideWidth(notchHeight: CGFloat, showsTask: Bool = false) -> CGFloat {
        showsTask ? taskSideWidth : max(notchHeight - 12, 40)
    }

    /// The task name only shows while focusing; a break isn't time spent on it
    @MainActor
    static func showsTask(_ focus: FocusTimerManager) -> Bool {
        focus.task != nil && focus.phase == .focus && focus.state != .finished
    }

    var body: some View {
        let iconSize = max(0, vm.effectiveClosedNotchHeight - 14)
        let showsTask = Self.showsTask(focus)
        let sideWidth = Self.sideWidth(notchHeight: vm.effectiveClosedNotchHeight, showsTask: showsTask)

        HStack {
            HStack(spacing: 5) {
                Group {
                    if focus.state == .finished {
                        Image(systemName: "checkmark.circle.fill")
                            .resizable()
                            .foregroundStyle(.green)
                    } else {
                        FocusProgressRing(progress: focus.progress, state: focus.state, lineWidth: 3, isBreak: focus.phase.isBreak)
                    }
                }
                .frame(width: iconSize, height: iconSize)

                if showsTask, let task = focus.task {
                    Text(task.title)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: sideWidth)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + -cornerRadiusInsets.closed.top)

            Text(focus.state == .finished ? "Done" : focus.remainingText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                // Mint during a break, like the ring, so a break never passes for focus time
                .foregroundStyle(focus.state == .paused ? .gray : focus.phase.isBreak ? .mint : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: sideWidth)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

/// Shown on the closed notch for a few seconds when a phase ends: what starts now, in that phase's color
struct FocusPhaseLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    let announcement: PhaseAnnouncement

    static let sideWidth: CGFloat = 96

    private var color: Color {
        switch announcement.next {
        case nil: return .green
        case .focus: return .orange
        case .shortBreak, .longBreak: return .mint
        }
    }

    private var icon: String {
        switch announcement.next {
        case nil: return "checkmark.circle.fill"
        case .focus: return "brain.head.profile"
        case .shortBreak, .longBreak: return "cup.and.saucer.fill"
        }
    }

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .symbolEffect(.pulse, options: .repeating)
                Text(announcement.phaseName)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(color)
            .frame(width: Self.sideWidth)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + -cornerRadiusInsets.closed.top)

            Text(announcement.detail)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: Self.sideWidth)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .help(announcement.title)
    }
}

#Preview {
    FocusTimerView()
        .frame(width: 600, height: 150)
        .background(.black)
}
