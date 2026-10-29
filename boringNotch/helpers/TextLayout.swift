//
//  TextLayout.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import Foundation

/// A piece of recognized text with its box in Vision's normalized coordinates (0...1, origin bottom left)
struct RecognizedFragment: Equatable {
    let text: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var midY: Double { y + height / 2 }
}

/// Puts OCR fragments back in reading order. Foundation only, so it can be tested without the app.
enum TextLayout {
    /// Fragments whose vertical middles are this close (in line heights) share a line
    static let sameLineTolerance = 0.5
    /// A gap bigger than this many line heights starts a new paragraph
    static let paragraphGap = 1.0

    /// Top to bottom, left to right; side-by-side fragments on one line are joined with a space,
    /// and a blank line separates paragraphs
    static func join(_ fragments: [RecognizedFragment]) -> String {
        let sorted = fragments
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.midY > $1.midY }
        var lines: [[RecognizedFragment]] = []
        for fragment in sorted {
            if let last = lines.last?.first,
               abs(last.midY - fragment.midY) <= max(last.height, fragment.height) * sameLineTolerance {
                lines[lines.count - 1].append(fragment)
            } else {
                lines.append([fragment])
            }
        }

        var output = ""
        var previous: (bottom: Double, height: Double)?
        for line in lines {
            let ordered = line.sorted { $0.x < $1.x }
            let text = ordered.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            let top = ordered.map { $0.y + $0.height }.max() ?? 0
            let bottom = ordered.map(\.y).min() ?? 0
            let height = ordered.map(\.height).max() ?? 0
            if let previous {
                output += (previous.bottom - top) > previous.height * paragraphGap ? "\n\n" : "\n"
            }
            output += text
            previous = (bottom, height)
        }
        return output
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}
