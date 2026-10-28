//
//  QuickCaptureTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-28.
//

import Foundation

func runQuickCaptureTests() {
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
    // A Wednesday afternoon
    let now = date("2026-10-28 14:30")
    func describe(_ text: String) -> String {
        switch QuickCapture.parse(text, now: now, calendar: calendar) {
        case nil:
            return "nil"
        case .note(let body)?:
            return "note: " + body
        case .todo(let title, let due)?:
            let label = due.map { TodoSchedule.dueLabel($0, now: now, calendar: calendar, locale: english) } ?? "none"
            return "todo: \(title) @ \(label)"
        }
    }

    check("capture task with date word", describe("beli kopi besok"), "todo: beli kopi @ Tomorrow")
    check("capture task without date is today", describe("review PR"), "todo: review PR @ Today")
    check("capture task with weekday", describe("call mom friday"), "todo: call mom @ Fri")
    check("capture task with lusa", describe("bayar listrik lusa"), "todo: bayar listrik @ Fri")
    check("capture trims spaces", describe("   beli kopi   "), "todo: beli kopi @ Today")
    check("capture empty", describe("   "), "nil")
    check("capture note prefix", describe("n: ide aplikasi baru"), "note: ide aplikasi baru")
    check("capture note prefix uppercase", describe("N: Idea"), "note: Idea")
    check("capture note long prefix", describe("note: meeting recap"), "note: meeting recap")
    check("capture catatan prefix", describe("catatan: resep"), "note: resep")
    check("capture note keeps date words", describe("n: rapat besok"), "note: rapat besok")
    check("capture note prefix only", describe("n:"), "nil")
    check("capture todo prefix", describe("t: n: is not a note besok"), "todo: n: is not a note @ Tomorrow")
    check("capture only date word stays title", describe("besok"), "todo: besok @ Today")

    check("destination note", QuickCapture.destination(of: .note("x"), now: now, calendar: calendar, locale: english), "Note")
    check("destination todo tomorrow",
          QuickCapture.destination(of: .todo(title: "x", due: date("2026-10-29 00:00")), now: now, calendar: calendar, locale: english),
          "To-do · Tomorrow")
    check("destination todo undated", QuickCapture.destination(of: .todo(title: "x", due: nil), now: now), "To-do")
}
