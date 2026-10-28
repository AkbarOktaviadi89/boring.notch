//
//  Meetings.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-28.
//

import Foundation

/// The parts of a calendar event the meeting countdown needs
struct MeetingCandidate: Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    /// False for reminders and birthdays
    let isEvent: Bool
    let isDeclined: Bool
    let joinURL: URL?
}

/// Which meeting to count down to. Foundation only, so it can be tested without the app.
enum MeetingSchedule {
    /// The countdown stays up this long after the start, for joining a little late
    static let joinGrace: TimeInterval = 5 * 60

    /// The earliest meeting starting within `lead`, or one that began less than `joinGrace` ago.
    /// All-day events, reminders and declined invitations never count.
    static func next(_ candidates: [MeetingCandidate], now: Date, lead: TimeInterval) -> MeetingCandidate? {
        guard lead > 0 else { return nil }
        return candidates
            .filter { meeting in
                meeting.isEvent && !meeting.isAllDay && !meeting.isDeclined
                    && meeting.start.timeIntervalSince(now) <= lead
                    && now < min(meeting.end, meeting.start.addingTimeInterval(joinGrace))
            }
            .min { $0.start < $1.start }
    }

    /// "8m" (rounded up, so it never says 0m early), "1h 5m", or "Now" once it has started
    static func countdown(to start: Date, now: Date) -> String {
        let seconds = start.timeIntervalSince(now)
        guard seconds > 0 else { return "Now" }
        let minutes = Int((seconds / 60).rounded(.up))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

/// Finds a video-call link in an event. Foundation only, so it can be tested without the app.
enum MeetingLink {
    /// Video-call services, matched against the host and its parent domains
    static let hosts = [
        "zoom.us", "zoom.com", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "whereby.com", "meet.jit.si", "facetime.apple.com", "chime.aws", "gotomeeting.com",
    ]
    /// App links that open the call directly
    static let schemes = ["zoommtg", "msteams"]

    /// The event's own URL wins, then links in the location, then in the notes
    static func joinURL(url: URL?, location: String?, notes: String?) -> URL? {
        if let url, isMeeting(url) { return url }
        for text in [location, notes].compactMap({ $0 }) {
            if let link = links(in: text).first(where: isMeeting) { return link }
        }
        return nil
    }

    static func isMeeting(_ url: URL) -> Bool {
        if let scheme = url.scheme?.lowercased(), schemes.contains(scheme) { return true }
        guard let host = url.host?.lowercased() else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url)
    }
}
