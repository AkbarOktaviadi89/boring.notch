//
//  MeetingLiveActivity.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-28.
//

import SwiftUI

/// Shown on the closed notch shortly before a meeting: its title on the left, the minutes left on the right.
/// Opening the notch lands on Home, where the event has a Join button when it has a call link.
struct MeetingLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    let meeting: MeetingCandidate

    static let sideWidth: CGFloat = 104

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let started = meeting.start <= context.date
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: meeting.joinURL != nil ? "video.fill" : "calendar")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(started ? .green : .orange)
                    Text(meeting.title)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: Self.sideWidth)

                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width + -cornerRadiusInsets.closed.top)

                Text(MeetingSchedule.countdown(to: meeting.start, now: context.date))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(started ? .green : .white)
                    .lineLimit(1)
                    .frame(width: Self.sideWidth)
            }
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .help(meeting.title)
    }
}

/// A small "Join" capsule for events that carry a video-call link
struct MeetingJoinButton: View {
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label("Join", systemImage: "video.fill")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.green.opacity(0.85)))
                .foregroundStyle(.white)
        }
        .buttonStyle(PlainButtonStyle())
        .help(url.absoluteString)
    }
}
