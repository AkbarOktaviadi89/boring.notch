//
//  FocusTimerView.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Defaults
import SwiftUI

struct FocusTimerView: View {
    @ObservedObject var focus = FocusTimerManager.shared
    @Default(.focusTimerDuration) var duration

    var body: some View {
        HStack(spacing: 24) {
            FocusProgressRing(progress: focus.progress, state: focus.state, lineWidth: 8)
                .overlay {
                    VStack(spacing: 2) {
                        Text(focus.state == .finished ? "Done" : focus.remainingText)
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.smooth, value: focus.remainingText)
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }
                .frame(width: 120, height: 120)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Focus", systemImage: "timer")
                        .font(.headline)
                    Spacer()
                    Text("\(focus.completedToday) sessions today")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }

                durationPicker
                    .disabled(focus.isActive)
                    .opacity(focus.isActive ? 0.4 : 1)

                controls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusText: LocalizedStringKey {
        switch focus.state {
        case .idle: return "Ready"
        case .running: return "Focusing"
        case .paused: return "Paused"
        case .finished: return "Session complete"
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
            .disabled(focus.state == .idle)
            .opacity(focus.state == .idle ? 0.4 : 1)
        }
    }

    private var primaryLabel: LocalizedStringKey {
        switch focus.state {
        case .running: return "Pause"
        case .paused: return "Resume"
        case .idle, .finished: return "Start"
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

struct FocusProgressRing: View {
    let progress: Double
    let state: FocusTimerManager.State
    let lineWidth: CGFloat

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
        case .idle, .running: return .effectiveAccent
        }
    }
}

/// Shown on the closed notch while a focus session is running, paused or just finished
struct FocusLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var focus = FocusTimerManager.shared

    static func sideWidth(notchHeight: CGFloat) -> CGFloat {
        max(notchHeight - 12, 40)
    }

    var body: some View {
        let iconSize = max(0, vm.effectiveClosedNotchHeight - 14)
        let sideWidth = Self.sideWidth(notchHeight: vm.effectiveClosedNotchHeight)

        HStack {
            Group {
                if focus.state == .finished {
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .foregroundStyle(.green)
                } else {
                    FocusProgressRing(progress: focus.progress, state: focus.state, lineWidth: 3)
                }
            }
            .frame(width: iconSize, height: iconSize)
            .frame(width: sideWidth)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + -cornerRadiusInsets.closed.top)

            Text(focus.state == .finished ? "Done" : focus.remainingText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(focus.state == .paused ? .gray : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: sideWidth)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

#Preview {
    FocusTimerView()
        .frame(width: 600, height: 150)
        .background(.black)
}
