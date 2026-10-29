//
//  PasswordGeneratorTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import Foundation

/// Repeatable randomness for tests (SplitMix64)
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func runPasswordGeneratorTests() {
    var rng = SeededGenerator(state: 42)

    var options = PasswordOptions()
    var allOK = true
    for _ in 0..<200 {
        let password = PasswordGenerator.password(options, using: &rng)
        let ok = password.count == 20 && password.contains(where: \.isUppercase) && password.contains(where: \.isLowercase)
            && password.contains(where: \.isNumber) && password.contains(where: { !$0.isLetter && !$0.isNumber })
        if !ok { allOK = false }
    }
    check("password has every set", String(allOK), "true")

    options.length = 12
    options.symbols = false
    options.uppercase = false
    let simple = PasswordGenerator.password(options, using: &rng)
    check("password only chosen sets", String(simple.allSatisfy { $0.isLowercase || $0.isNumber }), "true")
    check("password length", String(simple.count), "12")

    options = PasswordOptions(length: 30, avoidAmbiguous: true)
    var clear = true
    for _ in 0..<100 where PasswordGenerator.password(options, using: &rng).contains(where: { "0O1lI".contains($0) }) {
        clear = false
    }
    check("password avoids ambiguous", String(clear), "true")

    check("password clamps length", String(PasswordGenerator.password(PasswordOptions(length: 3), using: &rng).count), "8")
    check("password no sets", PasswordGenerator.password(PasswordOptions(uppercase: false, lowercase: false, digits: false, symbols: false), using: &rng), "")

    let words = ["kopi", "hujan", "pagi", "kucing", "laut"]
    let phrase = PasswordGenerator.passphrase(words: words, count: 4, separator: "-", capitalize: true, addNumber: true, using: &rng)
    let parts = phrase.split(separator: "-")
    check("passphrase parts", String(parts.count), "5")
    check("passphrase capitalized", String(parts.prefix(4).allSatisfy { $0.first?.isUppercase == true }), "true")
    check("passphrase number", String(Int(parts.last ?? "") != nil), "true")
    check("passphrase plain", String(PasswordGenerator.passphrase(words: ["a"], count: 3, separator: " ", capitalize: false, addNumber: false, using: &rng)), "a a a")

    // Entropy and strength
    check("entropy full set 20", String(format: "%.0f", PasswordGenerator.entropy(PasswordOptions())), "129")
    check("entropy digits only", String(format: "%.1f", PasswordGenerator.entropy(PasswordOptions(length: 10, uppercase: false, lowercase: false, symbols: false))), "33.2")
    check("passphrase entropy", String(format: "%.1f", PasswordGenerator.passphraseEntropy(listSize: 65536, count: 5, addNumber: false)), "80.0")
    check("strength weak", PasswordGenerator.strength(bits: 33).label, "Weak")
    check("strength strong", PasswordGenerator.strength(bits: 70).label, "Strong")
    check("strength very", PasswordGenerator.strength(bits: 129).label, "Very strong")
    check("typed estimate", String(format: "%.0f", PasswordGenerator.estimatedEntropy(of: "abc123")), "31")

    // Word list
    let list = PasswordGenerator.wordList(from: "Aaron\ncat\nkopi\nhujan\nkopi\nsupercalifragilistic\nnaïve\nlaut\n")
    check("word list filters", list.joined(separator: ","), "kopi,hujan,laut")
}
