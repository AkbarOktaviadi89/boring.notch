//
//  FocusStatsView.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import SwiftUI

/// Focused time over the last 7 days, the weekly total and the current streak
struct FocusStatsView: View {
    @ObservedObject var focus = FocusTimerManager.shared

    var body: some View {
        // Re-render around midnight so "today" moves on while the tab stays open
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let days = StudyStats.lastDays(7, endingOn: context.date, log: focus.studyLog)
            let weekTotal = days.reduce(0) { $0 + $1.seconds }
            let today = days.last?.seconds ?? 0
            let streak = StudyStats.streak(endingOn: context.date, log: focus.studyLog)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    FocusSectionPicker()
                    Spacer()
                }
                HStack(alignment: .top, spacing: 16) {
                    WeekBars(days: days)
                        .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 8) {
                        summary("Today", StudyStats.formatDuration(today))
                        summary("Last 7 days", StudyStats.formatDuration(weekTotal))
                        summary("Streak", streak == 1 ? "1 day" : "\(streak) days")
                    }
                    .frame(width: 130, alignment: .leading)
                }
            }
        }
    }

    private func summary(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.gray)
            Text(value)
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
    }
}

private struct WeekBars: View {
    let days: [StudyDay]

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter
    }()

    var body: some View {
        let longest = max(days.map(\.seconds).max() ?? 0, 60)
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                let isToday = index == days.count - 1
                VStack(spacing: 3) {
                    GeometryReader { geo in
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isToday ? Color.effectiveAccent : Color.effectiveAccent.opacity(0.45))
                                .frame(height: day.seconds == 0 ? 2 : max(4, geo.size.height * CGFloat(day.seconds) / CGFloat(longest)))
                        }
                    }
                    Text(Self.weekday.string(from: day.date))
                        .font(.caption2)
                        .foregroundStyle(isToday ? .white : .gray)
                }
                .help("\(day.date.formatted(date: .abbreviated, time: .omitted)): \(StudyStats.formatDuration(day.seconds))")
            }
        }
        .frame(height: 92)
        .animation(.smooth, value: days)
    }
}

#Preview {
    FocusStatsView()
        .frame(width: 600, height: 130)
        .background(.black)
}
