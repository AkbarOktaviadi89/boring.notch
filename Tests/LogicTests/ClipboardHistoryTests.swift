//
//  ClipboardHistoryTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import Foundation

func runClipboardHistoryTests() {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    func entry(_ text: String, _ minutes: Double, pinned: Bool = false, app: String? = nil) -> ClipEntry {
        ClipEntry(text: text, sourceApp: app, isPinned: pinned, copiedAt: base.addingTimeInterval(minutes * 60))
    }
    func texts(_ list: [ClipEntry]) -> String { list.map { $0.text ?? "[image]" }.joined(separator: ",") }

    // Adding
    let a = entry("alpha", 1), b = entry("beta", 2)
    check("add on top", texts(ClipboardHistory.adding(b, to: [a]).list), "beta,alpha")
    let pinnedA = entry("alpha", 1, pinned: true)
    let again = ClipboardHistory.adding(entry("alpha", 5), to: [b, pinnedA])
    check("copy again moves up", texts(again.list), "alpha,beta")
    check("copy again keeps pin", String(again.list[0].isPinned), "true")
    check("copy again keeps id", String(again.list[0].id == pinnedA.id), "true")

    var many: [ClipEntry] = [entry("keep me", 0, pinned: true)]
    var removedCount = 0
    for i in 1...55 {
        let result = ClipboardHistory.adding(entry("item \(i)", Double(i)), to: many)
        many = result.list
        removedCount += result.removed.count
    }
    check("limit unpinned", String(many.filter { !$0.isPinned }.count), "50")
    check("limit keeps pinned", String(many.contains { $0.text == "keep me" }), "true")
    check("limit reports removed", String(removedCount), "5")
    check("limit drops oldest", String(many.contains { $0.text == "item 5" }), "false")

    // Order and search
    let list = [entry("old note", 1), entry("pinned thing", 0, pinned: true), entry("https://github.com/x", 3, app: "Safari"), entry("Résumé draft", 2)]
    check("ordered pinned first", texts(ClipboardHistory.ordered(list)), "pinned thing,https://github.com/x,Résumé draft,old note")
    check("search words", texts(ClipboardHistory.search(list, query: "old NOTE")), "old note")
    check("search accents", texts(ClipboardHistory.search(list, query: "resume")), "Résumé draft")
    check("search app", texts(ClipboardHistory.search(list, query: "safari")), "https://github.com/x")
    check("search empty", String(ClipboardHistory.search(list, query: "  ").count), "4")
    let image = ClipEntry(imageFile: "a.png", copiedAt: base)
    check("search images", String(ClipboardHistory.search([image, a], query: "image").count), "1")

    // Kinds and text
    check("link entry", String(entry("https://a.com/x", 0).isLink), "true")
    check("text with link not link", String(entry("see https://a.com", 0).isLink), "false")
    check("preview collapses", ClipboardHistory.preview("  one\n\n two\tthree  "), "one two three")
    check("preview cuts", ClipboardHistory.preview(String(repeating: "a", count: 300), length: 10), "aaaaaaaaa…")
    check("keep blank", String(ClipboardHistory.shouldKeep("  \n")), "false")
    check("keep huge", String(ClipboardHistory.shouldKeep(String(repeating: "x", count: 100_001))), "false")
    check("keep normal", String(ClipboardHistory.shouldKeep("hello")), "true")
}
