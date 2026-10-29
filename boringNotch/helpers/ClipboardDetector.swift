//
//  ClipboardDetector.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Foundation

enum ClipboardKind: Equatable {
    case jwt
    case json
    case timestamp
    /// URL, Base64, hex, HTML entity or unicode escape encoding that the smart decoder can peel off
    case encoded
    /// A long web link worth shortening
    case link
    /// Prose in another language than the user's; decided by ClipboardWatcher, which can detect languages
    case translate
}

/// Recognizes copied text worth opening in Dev Tools. Foundation only, so it can be tested without the app.
enum ClipboardDetector {
    /// Bigger clipboards are skipped so copying a large file's text never stalls the app
    static let maxLength = 200_000

    /// Unix timestamps between 2000-01-01 and 2100-01-01; other 10 or 13 digit numbers are likely ids
    private static let plausibleSeconds: ClosedRange<Double> = 946_684_800...4_102_444_800

    static func detect(_ text: String) -> ClipboardKind? {
        guard text.utf16.count <= maxLength else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if matches(trimmed, #"^(?i:bearer\s+)?eyJ[A-Za-z0-9_-]*\.eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]*$"#),
           (try? SecurityTransforms.decodeJWT(trimmed)) != nil {
            return .jwt
        }
        if let first = trimmed.first, first == "{" || first == "[",
           let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)),
           object is [Any] || object is [String: Any] {
            return .json
        }
        if matches(trimmed, #"^\d{10}(\d{3})?$"#), let value = Double(trimmed) {
            let seconds = trimmed.count == 13 ? value / 1000 : value
            if plausibleSeconds.contains(seconds) { return .timestamp }
        }
        if (try? SecurityTransforms.smartDecode(trimmed)) != nil {
            return .encoded
        }
        // After decoding: a link carrying an encoded payload is more likely being inspected than shared
        if ShortLinks.worthShortening(trimmed) {
            return .link
        }
        return nil
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
