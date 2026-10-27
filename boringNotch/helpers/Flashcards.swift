//
//  Flashcards.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Foundation

struct Flashcard: Codable, Identifiable, Equatable {
    var id = UUID()
    var front: String
    var back: String
    /// Leitner box: 0 for a card never reviewed, then 1...5
    var box = 0
    var due: Date
    var createdAt: Date

    init(front: String, back: String, createdAt: Date = Date()) {
        self.front = front
        self.back = back
        self.createdAt = createdAt
        self.due = createdAt
    }

    func isDue(at now: Date) -> Bool {
        due <= now
    }
}

/// Leitner spaced repetition: each remembered card moves up a box and waits longer before coming back.
/// Foundation only, so it can be tested without the app.
enum Leitner {
    static let maxBox = 5
    /// Wait after a "Good" answer, by the box the card lands in
    static let intervals: [Int: TimeInterval] = [1: 1, 2: 3, 3: 7, 4: 14, 5: 30].mapValues { $0 * 86_400 }
    /// A forgotten card comes back within the same study session
    static let againDelay: TimeInterval = 10 * 60

    static func review(_ card: Flashcard, remembered: Bool, at now: Date) -> Flashcard {
        var card = card
        if remembered {
            card.box = min(maxBox, card.box + 1)
            card.due = now.addingTimeInterval(intervals[card.box] ?? 0)
        } else {
            card.box = 1
            card.due = now.addingTimeInterval(againDelay)
        }
        return card
    }

    /// Cards to review now, the longest overdue first
    static func dueCards(_ cards: [Flashcard], at now: Date) -> [Flashcard] {
        cards.filter { $0.isDue(at: now) }.sorted { $0.due < $1.due }
    }

    /// One card per "front :: back" line; lines without both sides are skipped
    static func parseBulk(_ text: String) -> [(front: String, back: String)] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let separator = line.range(of: "::") else { return nil }
            let front = line[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
            let back = line[separator.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !front.isEmpty, !back.isEmpty else { return nil }
            return (front, back)
        }
    }
}
