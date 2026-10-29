//
//  PasswordGenerator.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import Foundation

struct PasswordOptions: Equatable {
    var length = 20
    var uppercase = true
    var lowercase = true
    var digits = true
    var symbols = true
    /// Leaves out 0/O, 1/l/I and similar, for passwords someone has to type
    var avoidAmbiguous = false
}

enum PasswordStrength: Int, Comparable {
    case weak, fair, strong, veryStrong

    var label: String {
        switch self {
        case .weak: return "Weak"
        case .fair: return "Fair"
        case .strong: return "Strong"
        case .veryStrong: return "Very strong"
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Passwords and passphrases. Pass SystemRandomNumberGenerator, which is cryptographically secure on Apple platforms;
/// tests pass a seeded one. Foundation only, so it can be tested without the app.
enum PasswordGenerator {
    static let lengthRange = 8...64
    static let wordCountRange = 3...10

    private static let upper = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let lower = Array("abcdefghijklmnopqrstuvwxyz")
    private static let digitSet = Array("0123456789")
    private static let symbolSet = Array("!@#$%^&*()-_=+[]{};:,.?/~")
    private static let ambiguous = Set("0O1lI|5S2Z8B")

    static func characterSets(_ options: PasswordOptions) -> [[Character]] {
        var sets: [[Character]] = []
        if options.uppercase { sets.append(upper) }
        if options.lowercase { sets.append(lower) }
        if options.digits { sets.append(digitSet) }
        if options.symbols { sets.append(symbolSet) }
        if options.avoidAmbiguous { sets = sets.map { $0.filter { !ambiguous.contains($0) } } }
        return sets.filter { !$0.isEmpty }
    }

    /// At least one character from every chosen set, then shuffled so they don't sit at the start
    static func password<R: RandomNumberGenerator>(_ options: PasswordOptions, using rng: inout R) -> String {
        let sets = characterSets(options)
        guard !sets.isEmpty else { return "" }
        let length = min(max(options.length, max(lengthRange.lowerBound, sets.count)), lengthRange.upperBound)
        let pool = sets.flatMap { $0 }
        var characters = sets.map { $0.randomElement(using: &rng)! }
        while characters.count < length {
            characters.append(pool.randomElement(using: &rng)!)
        }
        characters.shuffle(using: &rng)
        return String(characters)
    }

    /// Words joined by a separator, each capitalized, with a number at the end when asked
    static func passphrase<R: RandomNumberGenerator>(words: [String], count: Int, separator: String,
                                                     capitalize: Bool, addNumber: Bool, using rng: inout R) -> String {
        guard !words.isEmpty else { return "" }
        let count = min(max(count, wordCountRange.lowerBound), wordCountRange.upperBound)
        var picked = (0..<count).map { _ in words.randomElement(using: &rng)! }
        if capitalize { picked = picked.map { $0.prefix(1).uppercased() + $0.dropFirst() } }
        var phrase = picked.joined(separator: separator)
        if addNumber { phrase += separator + String(Int.random(in: 10...99, using: &rng)) }
        return phrase
    }

    /// Bits of entropy for a password built from these options
    static func entropy(_ options: PasswordOptions) -> Double {
        let pool = characterSets(options).reduce(0) { $0 + $1.count }
        guard pool > 1 else { return 0 }
        return Double(options.length) * log2(Double(pool))
    }

    static func passphraseEntropy(listSize: Int, count: Int, addNumber: Bool) -> Double {
        guard listSize > 1 else { return 0 }
        return Double(count) * log2(Double(listSize)) + (addNumber ? log2(90) : 0)
    }

    /// Bits for text someone typed, judged by the kinds of characters in it. Generous: it can't spot dictionary words.
    static func estimatedEntropy(of text: String) -> Double {
        var pool = 0
        if text.contains(where: \.isUppercase) { pool += 26 }
        if text.contains(where: \.isLowercase) { pool += 26 }
        if text.contains(where: \.isNumber) { pool += 10 }
        if text.contains(where: { !$0.isLetter && !$0.isNumber }) { pool += 32 }
        guard pool > 1 else { return 0 }
        return Double(text.count) * log2(Double(pool))
    }

    static func strength(bits: Double) -> PasswordStrength {
        switch bits {
        case ..<40: return .weak
        case ..<60: return .fair
        case ..<80: return .strong
        default: return .veryStrong
        }
    }

    /// Plain lowercase words of 4 to 8 letters from a dictionary file, one per line
    static func wordList(from dictionary: String) -> [String] {
        var seen = Set<String>()
        return dictionary.split(whereSeparator: \.isNewline).compactMap { line in
            let word = String(line)
            guard (4...8).contains(word.count), word.allSatisfy({ $0.isASCII && $0.isLowercase }),
                  seen.insert(word).inserted else { return nil }
            return word
        }
    }
}
