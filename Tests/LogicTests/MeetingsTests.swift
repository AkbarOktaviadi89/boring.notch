//
//  MeetingsTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-28.
//

import Foundation

func runMeetingsTests() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func meeting(_ id: String, inMinutes start: Double, lasting minutes: Double = 30,
                 allDay: Bool = false, event: Bool = true, declined: Bool = false) -> MeetingCandidate {
        let begin = now.addingTimeInterval(start * 60)
        return MeetingCandidate(
            id: id, title: id, start: begin, end: begin.addingTimeInterval(minutes * 60),
            isAllDay: allDay, isEvent: event, isDeclined: declined, joinURL: nil
        )
    }
    func next(_ candidates: [MeetingCandidate], lead: Double = 10) -> String {
        MeetingSchedule.next(candidates, now: now, lead: lead * 60)?.id ?? "none"
    }

    // Which meeting
    check("meeting within lead", next([meeting("standup", inMinutes: 8)]), "standup")
    check("meeting too far ahead", next([meeting("later", inMinutes: 25)]), "none")
    check("meeting at the lead edge", next([meeting("edge", inMinutes: 10)]), "edge")
    check("meeting earliest wins", next([meeting("b", inMinutes: 9), meeting("a", inMinutes: 3)]), "a")
    check("meeting just started", next([meeting("now", inMinutes: -2)]), "now")
    check("meeting past grace", next([meeting("old", inMinutes: -6)]), "none")
    check("meeting short and over", next([meeting("quick", inMinutes: -3, lasting: 2)]), "none")
    check("meeting skips all-day", next([meeting("holiday", inMinutes: 5, allDay: true)]), "none")
    check("meeting skips reminders", next([meeting("todo", inMinutes: 5, event: false)]), "none")
    check("meeting skips declined", next([meeting("nope", inMinutes: 5, declined: true), meeting("yes", inMinutes: 7)]), "yes")
    check("meeting off when lead is zero", next([meeting("standup", inMinutes: 1)], lead: 0), "none")

    // Countdown text
    check("countdown rounds up", MeetingSchedule.countdown(to: now.addingTimeInterval(7 * 60 + 5), now: now), "8m")
    check("countdown last seconds", MeetingSchedule.countdown(to: now.addingTimeInterval(20), now: now), "1m")
    check("countdown started", MeetingSchedule.countdown(to: now, now: now), "Now")
    check("countdown hours", MeetingSchedule.countdown(to: now.addingTimeInterval(65 * 60), now: now), "1h 5m")

    // Join links
    func join(url: String? = nil, location: String? = nil, notes: String? = nil) -> String {
        MeetingLink.joinURL(url: url.flatMap(URL.init(string:)), location: location, notes: notes)?.absoluteString ?? "none"
    }
    check("join from event url", join(url: "https://us02web.zoom.us/j/123"), "https://us02web.zoom.us/j/123")
    check("join ignores other event url", join(url: "https://example.com/agenda"), "none")
    check("join from location", join(location: "https://meet.google.com/abc-defg-hij"), "https://meet.google.com/abc-defg-hij")
    check("join from notes text",
          join(notes: "Agenda: https://docs.example.com/x\nJoin: https://teams.microsoft.com/l/meetup-join/19%3a"),
          "https://teams.microsoft.com/l/meetup-join/19%3a")
    check("join prefers url over notes",
          join(url: "https://zoom.us/j/1", notes: "https://meet.google.com/x"), "https://zoom.us/j/1")
    check("join location beats notes",
          join(location: "https://meet.google.com/a", notes: "https://zoom.us/j/2"), "https://meet.google.com/a")
    check("join none in room name", join(location: "Room 4B", notes: "Bring slides"), "none")
    check("join not fooled by lookalike", join(location: "https://notzoom.us.example.com/j/1"), "none")
    check("join app scheme", join(url: "zoommtg://zoom.us/join?confno=1"), "zoommtg://zoom.us/join?confno=1")
}
