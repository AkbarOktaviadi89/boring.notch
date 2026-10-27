//
//  NotesTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Foundation

func runNotesTests() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
    let english = Locale(identifier: "en_US_POSIX")
    func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = english
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    // Titles
    check("title first line", NoteText.title(of: "Meeting notes\nsecond line"), "Meeting notes")
    check("title skips blank lines", NoteText.title(of: "\n\n   \n  Idea  \nmore"), "Idea")
    check("title empty", NoteText.title(of: ""), "New note")
    check("title whitespace only", NoteText.title(of: "  \n\t\n"), "New note")
    check("title strips heading", NoteText.title(of: "## SQL injection payloads"), "SQL injection payloads")
    check("title strips list mark", NoteText.title(of: "- buy milk"), "buy milk")
    check("title strips checklist", NoteText.title(of: "- [ ] deploy api"), "deploy api")
    check("title only marks", NoteText.title(of: "###"), "New note")
    let long = String(repeating: "a", count: 80)
    check("title truncated length", "\(NoteText.title(of: long).count)", "60")
    check("title truncated ellipsis", "\(NoteText.title(of: long).hasSuffix("…"))", "true")

    // Previews
    check("preview second line", NoteText.preview(of: "Title\n\n  body text"), "body text")
    check("preview none", NoteText.preview(of: "Only a title"), "")
    check("preview strips quote", NoteText.preview(of: "Title\n> quoted"), "quoted")

    // Word count
    check("words", "\(NoteText.wordCount(of: "one two\nthree\t four  "))", "4")
    check("words empty", "\(NoteText.wordCount(of: "   "))", "0")

    // Blank
    check("blank", "\(Note(text: " \n ").isBlank)", "true")
    check("not blank", "\(Note(text: "x").isBlank)", "false")

    // Ordering: pinned first, then newest edit
    var old = Note(text: "old", createdAt: date("2026-10-20 10:00"))
    var recent = Note(text: "recent", createdAt: date("2026-10-27 09:00"))
    var pinned = Note(text: "pinned", isPinned: true, createdAt: date("2026-10-01 10:00"))
    check("sorted", NoteText.sorted([old, pinned, recent]).map(\.text).joined(separator: ","), "pinned,recent,old")
    old.updatedAt = date("2026-10-27 12:00")
    check("sorted after edit", NoteText.sorted([old, pinned, recent]).map(\.text).joined(separator: ","), "pinned,old,recent")
    pinned.isPinned = false
    recent.isPinned = true
    check("sorted pin moved", NoteText.sorted([old, pinned, recent]).map(\.text).joined(separator: ","), "recent,old,pinned")

    // Search
    let notes = [
        Note(text: "Recon checklist\nsubfinder, httpx, nuclei", createdAt: date("2026-10-27 08:00")),
        Note(text: "Belajar Swift\nstruct vs class", createdAt: date("2026-10-26 08:00")),
        Note(text: "Café ideas", createdAt: date("2026-10-25 08:00")),
    ]
    check("search empty query", "\(NoteText.search(notes, query: "  ").count)", "3")
    check("search case insensitive", NoteText.search(notes, query: "SWIFT").map { NoteText.title(of: $0.text) }.joined(separator: ","), "Belajar Swift")
    check("search body", "\(NoteText.search(notes, query: "nuclei").count)", "1")
    check("search all words", "\(NoteText.search(notes, query: "recon httpx").count)", "1")
    check("search all words miss", "\(NoteText.search(notes, query: "recon swift").count)", "0")
    check("search accents", "\(NoteText.search(notes, query: "cafe").count)", "1")

    // Date labels
    let now = date("2026-10-27 15:00")
    func label(_ text: String) -> String {
        NoteText.dateLabel(date(text), now: now, calendar: calendar, locale: english)
    }
    check("label today", label("2026-10-27 09:05"), "09:05")
    check("label yesterday", label("2026-10-26 23:59"), "Yesterday")
    check("label this week", label("2026-10-23 10:00"), "Fri")
    check("label older", label("2026-10-10 10:00"), "10 Oct")
}
