//
//  AssistantPlan.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-30.
//

import Foundation

enum AssistantAction: String, CaseIterable, Identifiable {
    case summarize = "Summarize"
    case formal = "Formal"
    case shorter = "Shorter"
    case friendly = "Friendly"
    case todos = "To-dos"

    var id: Self { self }

    var icon: String {
        switch self {
        case .summarize: return "text.append"
        case .formal: return "briefcase"
        case .shorter: return "arrow.down.right.and.arrow.up.left"
        case .friendly: return "face.smiling"
        case .todos: return "checklist"
        }
    }

    /// The model's instructions. It answers in English: the on-device model doesn't take Indonesian,
    /// so Indonesian text is translated on the way in and the answer on the way out.
    var instructions: String {
        let keepFacts = "Keep names, dates, times, numbers and amounts exactly as written. Do not add anything that is not in the text, and never guess a date or a day of the week."
        switch self {
        case .summarize:
            return "Summarize the text in at most 5 short bullet points, each starting with \"- \". \(keepFacts) Output only the bullet points."
        case .formal:
            return "Rewrite the text in a formal, polite tone suitable for a lecturer, a client or a manager. \(keepFacts) Output only the rewritten text."
        case .shorter:
            return "Rewrite the text to about half its length, keeping every important point. \(keepFacts) Output only the rewritten text."
        case .friendly:
            return "Rewrite the text in a warm, casual tone for a friend or a classmate. \(keepFacts) Output only the rewritten text."
        case .todos:
            return "List the tasks the reader has to do according to the text. Give each a title of 3 to 8 words that starts with a verb and says what the task is about, never just a verb. Only use a due date when the text states one or clearly implies it. Do not invent tasks."
        }
    }
}

/// Which text to offer, and tidying what comes back. Foundation only, so it can be tested without the app.
enum AssistantPlan {
    /// Shorter text is quicker to read than its summary
    static let minimumWordsToOffer = 80
    /// The model's context is small; longer text is cut to its first part
    static let maximumWords = 1_500

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// The clipboard hint: long prose, not code or data
    static func shouldOfferSummary(_ text: String) -> Bool {
        let words = wordCount(text)
        guard words >= minimumWordsToOffer else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let visible = trimmed.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
        guard visible > 0, Double(letters) / Double(visible) >= 0.75 else { return false }
        let codeMarks = ["{", "};", "=>", "();", "</", "def ", "func ", "const "]
        return codeMarks.filter { trimmed.contains($0) }.count < 2
    }

    /// The first `maximumWords` words, and whether anything was cut
    static func clipped(_ text: String) -> (text: String, wasCut: Bool) {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard words.count > maximumWords else { return (text.trimmingCharacters(in: .whitespacesAndNewlines), false) }
        return (words.prefix(maximumWords).joined(separator: " "), true)
    }

    /// One bullet per line with "- ", no blank lines between them (translation tends to add some)
    static func tidy(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let isList = lines.filter { !$0.isEmpty }.allSatisfy { $0.hasPrefix("-") || $0.hasPrefix("•") || $0.hasPrefix("*") }
        guard isList else {
            // Prose keeps its paragraphs, but never more than one blank line
            var result: [String] = []
            for line in lines where !(line.isEmpty && (result.last?.isEmpty ?? true)) { result.append(line) }
            return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return lines.filter { !$0.isEmpty }.map { line in
            var body = line
            while let first = body.first, "-•*".contains(first) { body.removeFirst() }
            return "- " + body.trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n")
    }

    /// "2026-11-07" -> the start of that day; anything else -> nil
    static func dueDate(_ text: String, calendar: Calendar = .current) -> Date? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (2000...2100).contains(parts[0]), (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
