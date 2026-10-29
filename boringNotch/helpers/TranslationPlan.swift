//
//  TranslationPlan.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import Foundation

/// Which way to translate and which copied text is worth offering. Foundation only, so it can be tested without the app.
/// The language itself is detected by NaturalLanguage in the app and passed in as a BCP 47 code.
enum TranslationPlan {
    static let home = "id"
    static let foreign = "en"
    /// Longer text is better pasted into a real translator
    static let maxLength = 5_000

    /// Indonesian goes to English; anything else comes to Indonesian
    static func direction(detected: String?) -> (source: String, target: String) {
        detected?.hasPrefix(home) == true ? (home, foreign) : (foreign, home)
    }

    /// Prose, not code, links or numbers: at least three words, mostly letters
    static func looksLikeProse(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= maxLength else { return false }
        let words = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard words.count >= 3 else { return false }
        if words.contains(where: { $0.contains("://") }) && words.count < 6 { return false }
        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let visible = trimmed.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
        guard visible > 0, Double(letters) / Double(visible) >= 0.75 else { return false }
        // Code: braces, semicolons at line ends, assignments
        let codeMarks = ["{", "};", "=>", "();", "</", "def ", "func ", "const ", "import "]
        return !codeMarks.contains { trimmed.contains($0) }
    }

    /// The clipboard hint only offers to translate text that isn't already in the user's language
    static func shouldOffer(_ text: String, detected: String?) -> Bool {
        guard let detected, looksLikeProse(text) else { return false }
        return !detected.hasPrefix(home)
    }
}
