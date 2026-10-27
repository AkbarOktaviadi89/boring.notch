//
//  FlashcardManager.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import AppKit
import Combine
import Defaults

extension Flashcard: Defaults.Serializable {}

@MainActor
final class FlashcardManager: ObservableObject {
    static let shared = FlashcardManager()

    @Published private(set) var cards: [Flashcard] = Defaults[.flashcards] {
        didSet { Defaults[.flashcards] = cards }
    }
    /// Whether the answer of the current card is showing
    @Published var isRevealed = false
    /// Text typed into the add form, kept when the notch closes mid-typing
    @Published var draftFront = ""
    @Published var draftBack = ""

    private init() {}

    func dueCards(at now: Date = Date()) -> [Flashcard] {
        Leitner.dueCards(cards, at: now)
    }

    /// When the next card that isn't due yet comes back
    func nextDueDate(after now: Date = Date()) -> Date? {
        cards.filter { !$0.isDue(at: now) }.map(\.due).min()
    }

    func review(_ card: Flashcard, remembered: Bool) {
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return }
        cards[index] = Leitner.review(cards[index], remembered: remembered, at: Date())
        isRevealed = false
    }

    func addDraft() {
        let front = draftFront.trimmingCharacters(in: .whitespacesAndNewlines)
        let back = draftBack.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !front.isEmpty, !back.isEmpty else { return }
        cards.append(Flashcard(front: front, back: back))
        draftFront = ""
        draftBack = ""
    }

    /// Adds one card per "front :: back" line on the clipboard; returns how many were added
    @discardableResult
    func addFromClipboard() -> Int {
        guard let text = NSPasteboard.general.string(forType: .string) else { return 0 }
        let pairs = Leitner.parseBulk(text)
        cards.append(contentsOf: pairs.map { Flashcard(front: $0.front, back: $0.back) })
        return pairs.count
    }

    func delete(_ card: Flashcard) {
        cards.removeAll { $0.id == card.id }
        isRevealed = false
    }
}
