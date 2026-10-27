//
//  MonthCalendarView.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Defaults
import SwiftUI

/// The whole month on the left, the events of the selected day on the right.
/// Takes the full width of the home tab; the day wheel view is CalendarView.
struct MonthCalendarView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.calendarMonthView) private var monthView
    @State private var displayedMonth = Date()
    @State private var selectedDate = Date()

    private let calendar = Calendar.current
    private let rowHeight: CGFloat = 14

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 2) {
                header
                weekdayRow
                grid
            }
            .frame(width: 252)

            VStack(alignment: .leading, spacing: 4) {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                let events = EventListView.filteredEvents(events: calendarManager.events)
                if events.isEmpty {
                    EmptyEventsView(selectedDate: selectedDate)
                    Spacer(minLength: 0)
                } else {
                    EventListView(events: calendarManager.events)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(height: 120)
        .onAppear { showToday() }
        .onChange(of: vm.notchState) { _, state in
            if state == .open { showToday() }
        }
        .onChange(of: selectedDate) {
            Task { await calendarManager.updateCurrentDate(selectedDate) }
        }
        .onChange(of: displayedMonth) {
            Task { await calendarManager.updateMonthEventDays(forMonthContaining: displayedMonth) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            if !calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
                || !calendar.isDateInToday(selectedDate) {
                Button("Today") { showToday() }
                    .font(.caption)
                    .buttonStyle(PlainButtonStyle())
                    .foregroundStyle(Color.effectiveAccent)
            }
            iconButton("chevron.left", help: "Previous month") { moveMonth(by: -1) }
            iconButton("chevron.right", help: "Next month") { moveMonth(by: 1) }
            iconButton("calendar.day.timeline.left", help: "Back to the day view") {
                withAnimation(.smooth) { monthView = false }
            }
        }
        .frame(height: 18)
    }

    private func iconButton(_ icon: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color(nsColor: .secondarySystemFill)))
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundStyle(.gray)
        .help(help)
    }

    // MARK: - Grid

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(MonthGrid.weekdaySymbols(calendar.veryShortStandaloneWeekdaySymbols, firstWeekday: calendar.firstWeekday).enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 12)
    }

    private var grid: some View {
        let days = MonthGrid.days(forMonthContaining: displayedMonth, calendar: calendar)
        return VStack(spacing: 0) {
            ForEach(0..<(days.count / 7), id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(days[(week * 7)..<(week * 7 + 7)], id: \.self) { day in
                        dayCell(day)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        let isToday = calendar.isDateInToday(day)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let hasEvents = calendarManager.monthEventDays.contains(StudyStats.dayKey(day, calendar: calendar))

        return Button {
            selectedDate = day
            if !inMonth { displayedMonth = day }
        } label: {
            HStack(spacing: 1) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 10, weight: isToday || isSelected ? .bold : .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? .white : (inMonth ? .white.opacity(0.9) : .gray.opacity(0.45)))
                Circle()
                    .fill(Color.effectiveAccent)
                    .frame(width: 3, height: 3)
                    .opacity(hasEvents ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight)
            .background(
                Capsule()
                    .fill(isToday ? Color.effectiveAccent : (isSelected ? Color.white.opacity(0.18) : .clear))
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Navigation

    private func moveMonth(by months: Int) {
        guard let month = calendar.date(byAdding: .month, value: months, to: displayedMonth) else { return }
        withAnimation(.smooth) { displayedMonth = month }
    }

    private func showToday() {
        displayedMonth = Date()
        selectedDate = Date()
        Task {
            await calendarManager.updateCurrentDate(selectedDate)
            await calendarManager.updateMonthEventDays(forMonthContaining: displayedMonth)
        }
    }
}
