//
//  DevTransforms.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Foundation

struct DevToolResult: Equatable {
    /// What the Copy button copies
    var primary: String
    /// Extra information shown under the result
    var detail: String?
}

struct DevToolError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Pure text transforms behind the Dev Tools tab. Foundation only, so they can be tested without the app.
enum DevTransforms {
    // MARK: JSON

    static func formatJSON(_ input: String) throws -> DevToolResult {
        try reencodeJSON(input, options: [.prettyPrinted, .sortedKeys])
    }

    static func minifyJSON(_ input: String) throws -> DevToolResult {
        try reencodeJSON(input, options: [])
    }

    private static func reencodeJSON(_ input: String, options: JSONSerialization.WritingOptions) throws -> DevToolResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DevToolError(message: "Nothing to format") }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: Data(trimmed.utf8), options: [.fragmentsAllowed])
        } catch {
            throw DevToolError(message: "Invalid JSON")
        }
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: options.union([.fragmentsAllowed, .withoutEscapingSlashes])
        )
        return DevToolResult(primary: String(decoding: data, as: UTF8.self), detail: "Valid JSON")
    }

    // MARK: Base64

    static func base64Encode(_ input: String) -> DevToolResult {
        DevToolResult(primary: Data(input.utf8).base64EncodedString())
    }

    /// Accepts URL-safe alphabet, missing padding and stray whitespace
    static func base64Data(_ input: String) -> Data? {
        var normalized = input.filter { !$0.isWhitespace }
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        guard !normalized.isEmpty else { return nil }
        return Data(base64Encoded: normalized)
    }

    static func base64Decode(_ input: String) throws -> DevToolResult {
        guard let data = base64Data(input) else {
            throw DevToolError(message: "Invalid Base64")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw DevToolError(message: "Decoded \(data.count) bytes, but they are not UTF-8 text")
        }
        return DevToolResult(primary: text)
    }

    // MARK: URL

    /// RFC 3986 unreserved characters are the only ones left as-is
    private static let urlUnreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    static func urlEncode(_ input: String) -> DevToolResult {
        DevToolResult(primary: input.addingPercentEncoding(withAllowedCharacters: urlUnreserved) ?? input)
    }

    /// Treats "+" as a space, as query strings do
    static func urlDecode(_ input: String) throws -> DevToolResult {
        guard let decoded = input.replacingOccurrences(of: "+", with: " ").removingPercentEncoding else {
            throw DevToolError(message: "Invalid percent-encoding")
        }
        return DevToolResult(primary: decoded)
    }

    // MARK: UUID

    static func uuid(uppercase: Bool) -> DevToolResult {
        let id = UUID().uuidString
        return DevToolResult(primary: uppercase ? id : id.lowercased())
    }

    // MARK: Timestamp

    /// A number becomes a date (seconds, or milliseconds when it is that large); a date becomes a Unix timestamp
    static func convertTimestamp(_ input: String, timeZone: TimeZone = .current) throws -> DevToolResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Double(trimmed) {
            let seconds = abs(value) >= 100_000_000_000 ? value / 1000 : value
            let date = Date(timeIntervalSince1970: seconds)
            return DevToolResult(
                primary: localFormatter(timeZone: timeZone, format: "yyyy-MM-dd HH:mm:ss zzz").string(from: date),
                detail: isoFormatter(fractional: false).string(from: date)
            )
        }
        guard let date = parseDate(trimmed, timeZone: timeZone) else {
            throw DevToolError(message: "Not a timestamp or a date like 2025-10-27 07:06:51")
        }
        let seconds = date.timeIntervalSince1970
        return DevToolResult(
            primary: String(Int64(seconds.rounded(.down))),
            detail: "\(Int64((seconds * 1000).rounded())) ms"
        )
    }

    private static func parseDate(_ input: String, timeZone: TimeZone) -> Date? {
        if let date = isoFormatter(fractional: true).date(from: input) ?? isoFormatter(fractional: false).date(from: input) {
            return date
        }
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            if let date = localFormatter(timeZone: timeZone, format: format).date(from: input) {
                return date
            }
        }
        return nil
    }

    static func localFormatter(timeZone: TimeZone, format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }

    private static func isoFormatter(fractional: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter
    }

    // MARK: Color

    /// Components are 0...1 sRGB
    static func color(red: Double, green: Double, blue: Double) -> DevToolResult {
        let r = Int((red * 255).rounded())
        let g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded())
        return DevToolResult(
            primary: String(format: "#%02X%02X%02X", r, g, b),
            detail: "rgb(\(r), \(g), \(b))"
        )
    }
}
