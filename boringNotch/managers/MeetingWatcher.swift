//
//  MeetingWatcher.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-28.
//

import AppKit
import Combine
import Defaults
import EventKit

extension EventModel {
    var meetingCandidate: MeetingCandidate {
        MeetingCandidate(
            id: id, title: title, start: start, end: end, isAllDay: isAllDay,
            isEvent: type.isEvent, isDeclined: attendance == .declined,
            joinURL: MeetingLink.joinURL(url: url, location: location, notes: notes)
        )
    }
}

/// Keeps the next meeting in view so the closed notch can count down to it
@MainActor
final class MeetingWatcher: ObservableObject {
    static let shared = MeetingWatcher()

    @Published private(set) var upcoming: MeetingCandidate?

    /// The meeting whose countdown already brought the notch to Home once
    private var acceptedKey: String?
    private var timer: Timer?
    private var defaultsObserver: Task<Void, Never>?

    private init() {}

    func start() {
        guard timer == nil else { return }
        // Calendar edits arrive through EKEventStoreChanged; this only notices time passing.
        // Meetings start on the minute, so once a minute is enough. The countdown ticks in the view.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        defaultsObserver = Task { [weak self] in
            for await _ in Defaults.updates(.meetingCountdownMinutes, initial: true) {
                await self?.refresh()
            }
        }
    }

    func refresh(now: Date = Date()) async {
        let lead = TimeInterval(Defaults[.meetingCountdownMinutes] * 60)
        guard lead > 0 else {
            upcoming = nil
            return
        }
        let events = await CalendarManager.shared.events(
            from: now.addingTimeInterval(-MeetingSchedule.joinGrace),
            to: now.addingTimeInterval(lead + 60)
        )
        let next = MeetingSchedule.next(events.map(\.meetingCandidate), now: now, lead: lead)
        if next != upcoming { upcoming = next }
    }

    /// Opens Home, where the meeting's Join button is, the first time the notch opens during a countdown.
    /// Later opens go wherever they normally would. Returns false when nothing was done.
    @discardableResult
    func accept() -> Bool {
        guard let upcoming, Defaults[.showCalendar] else { return false }
        // Recurring events share an id, so the start tells occurrences apart
        let key = upcoming.id + "@" + String(upcoming.start.timeIntervalSince1970)
        guard key != acceptedKey else { return false }
        acceptedKey = key
        BoringViewCoordinator.shared.currentView = .home
        return true
    }
}

