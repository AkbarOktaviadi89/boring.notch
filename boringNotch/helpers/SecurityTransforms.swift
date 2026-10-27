//
//  SecurityTransforms.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import CryptoKit
import Foundation

/// Decoders and encoders for the Security category of the Dev Tools tab.
/// Foundation and CryptoKit only, so they can be tested without the app.
enum SecurityTransforms {
    // MARK: JWT

    /// Decodes header and payload. The signature is never checked.
    static func decodeJWT(_ input: String, now: Date = Date(), timeZone: TimeZone = .current) throws -> DevToolResult {
        var token = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.lowercased().hasPrefix("bearer ") {
            token = String(token.dropFirst("bearer ".count)).trimmingCharacters(in: .whitespaces)
        }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2,
              let header = jsonObject(fromBase64URL: String(parts[0])),
              let payload = jsonObject(fromBase64URL: String(parts[1]))
        else {
            throw DevToolError(message: "Not a JWT (expected header.payload.signature)")
        }

        var lines = ["Header: \(try jsonString(header, pretty: false))"]
        if let alg = (header as? [String: Any])?["alg"] as? String, alg.lowercased() == "none" {
            lines.append("⚠️ alg is \"none\": the token is unsigned")
        }
        if let claims = payload as? [String: Any] {
            let formatter = DevTransforms.localFormatter(timeZone: timeZone, format: "yyyy-MM-dd HH:mm:ss zzz")
            if let exp = claims["exp"] as? Double {
                let expiry = Date(timeIntervalSince1970: exp)
                let status = expiry <= now ? "expired" : "valid for \(describe(expiry.timeIntervalSince(now)))"
                lines.append("exp: \(formatter.string(from: expiry)) (\(status))")
            }
            for claim in ["iat", "nbf"] {
                if let value = claims[claim] as? Double {
                    lines.append("\(claim): \(formatter.string(from: Date(timeIntervalSince1970: value)))")
                }
            }
        }
        lines.append("Signature not verified")

        return DevToolResult(primary: try jsonString(payload, pretty: true), detail: lines.joined(separator: "\n"))
    }

    private static func jsonObject(fromBase64URL part: String) -> Any? {
        guard let data = DevTransforms.base64Data(part) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private static func jsonString(_ object: Any, pretty: Bool) throws -> String {
        var options: JSONSerialization.WritingOptions = [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]
        if pretty { options.insert(.prettyPrinted) }
        return String(decoding: try JSONSerialization.data(withJSONObject: object, options: options), as: UTF8.self)
    }

    private static func describe(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes < 120 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 48 { return "\(hours) h" }
        return "\(hours / 24) days"
    }

    // MARK: Hash

    enum HashAlgorithm: String, CaseIterable, Identifiable {
        case md5 = "MD5"
        case sha1 = "SHA-1"
        case sha256 = "SHA-256"
        case sha512 = "SHA-512"

        var id: Self { self }
    }

    static func hash(_ input: String, _ algorithm: HashAlgorithm) -> DevToolResult {
        let data = Data(input.utf8)
        let digest: [UInt8]
        switch algorithm {
        case .md5: digest = Array(Insecure.MD5.hash(data: data))
        case .sha1: digest = Array(Insecure.SHA1.hash(data: data))
        case .sha256: digest = Array(SHA256.hash(data: data))
        case .sha512: digest = Array(SHA512.hash(data: data))
        }
        return DevToolResult(
            primary: digest.map { String(format: "%02x", $0) }.joined(),
            detail: "\(algorithm.rawValue) of \(data.count) UTF-8 bytes"
        )
    }

    // MARK: Hex

    static func hexEncode(_ input: String) -> DevToolResult {
        DevToolResult(primary: Data(input.utf8).map { String(format: "%02x", $0) }.joined())
    }

    /// Accepts "68 65", "0x6865", "\x68\x65" and "68:65"
    static func hexDecode(_ input: String) throws -> DevToolResult {
        let digits = input
            .replacingOccurrences(of: "\\x", with: "")
            .replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: "0X", with: "")
            .filter { !$0.isWhitespace && $0 != ":" && $0 != "," }
        guard !digits.isEmpty, digits.count.isMultiple(of: 2), digits.allSatisfy(\.isHexDigit) else {
            throw DevToolError(message: "Invalid hex (needs an even number of 0-9 a-f digits)")
        }
        var bytes = [UInt8]()
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            bytes.append(UInt8(digits[index..<next], radix: 16)!)
            index = next
        }
        guard let text = String(bytes: bytes, encoding: .utf8) else {
            throw DevToolError(message: "Decoded \(bytes.count) bytes, but they are not UTF-8 text")
        }
        return DevToolResult(primary: text)
    }

    // MARK: HTML entities

    static func htmlEncode(_ input: String) -> DevToolResult {
        var output = ""
        for character in input {
            switch character {
            case "&": output += "&amp;"
            case "<": output += "&lt;"
            case ">": output += "&gt;"
            case "\"": output += "&quot;"
            case "'": output += "&#39;"
            default: output.append(character)
            }
        }
        return DevToolResult(primary: output)
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
    ]

    /// Unknown named entities are left as they are
    static func htmlDecode(_ input: String) -> DevToolResult {
        let regex = try! NSRegularExpression(pattern: "&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);")
        var output = ""
        var last = input.startIndex
        for match in regex.matches(in: input, range: NSRange(input.startIndex..., in: input)) {
            guard let whole = Range(match.range, in: input), let body = Range(match.range(at: 1), in: input) else { continue }
            output += input[last..<whole.lowerBound]
            output += decodeEntity(String(input[body])) ?? String(input[whole])
            last = whole.upperBound
        }
        output += input[last...]
        return DevToolResult(primary: output)
    }

    private static func decodeEntity(_ body: String) -> String? {
        if body.hasPrefix("#x") || body.hasPrefix("#X") {
            return UInt32(body.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) }
        }
        if body.hasPrefix("#") {
            return UInt32(body.dropFirst()).flatMap(Unicode.Scalar.init).map { String($0) }
        }
        return namedEntities[body]
    }

    // MARK: Unicode escapes

    /// Escapes everything outside ASCII as \uXXXX, using surrogate pairs like JavaScript and JSON
    static func unicodeEscape(_ input: String) -> DevToolResult {
        var output = ""
        for unit in input.utf16 {
            if unit < 0x80, let scalar = Unicode.Scalar(unit) {
                output.unicodeScalars.append(scalar)
            } else {
                output += String(format: "\\u%04x", unit)
            }
        }
        return DevToolResult(primary: output)
    }

    /// Understands \uXXXX (with surrogate pairs), \u{XXXXX} and \xHH
    static func unicodeUnescape(_ input: String) throws -> DevToolResult {
        let scalars = Array(input.unicodeScalars)
        var output = String.UnicodeScalarView()
        var i = 0

        func hexValue(from start: Int, count: Int) -> UInt32? {
            guard start + count <= scalars.count else { return nil }
            let digits = String(String.UnicodeScalarView(scalars[start..<start + count]))
            guard digits.allSatisfy(\.isHexDigit) else { return nil }
            return UInt32(digits, radix: 16)
        }

        while i < scalars.count {
            guard scalars[i] == "\\", i + 1 < scalars.count else {
                output.append(scalars[i])
                i += 1
                continue
            }
            let marker = scalars[i + 1]
            if marker == "u", i + 2 < scalars.count, scalars[i + 2] == "{",
               let close = scalars[(i + 3)...].firstIndex(of: "}"),
               let value = hexValue(from: i + 3, count: close - (i + 3)),
               let scalar = Unicode.Scalar(value) {
                output.append(scalar)
                i = close + 1
            } else if marker == "u", let unit = hexValue(from: i + 2, count: 4) {
                if (0xD800...0xDBFF).contains(unit) {
                    guard i + 7 < scalars.count, scalars[i + 6] == "\\", scalars[i + 7] == "u",
                          let low = hexValue(from: i + 8, count: 4), (0xDC00...0xDFFF).contains(low),
                          let scalar = Unicode.Scalar(0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00))
                    else {
                        throw DevToolError(message: "Lone surrogate \\u\(String(unit, radix: 16))")
                    }
                    output.append(scalar)
                    i += 12
                } else if let scalar = Unicode.Scalar(unit) {
                    output.append(scalar)
                    i += 6
                } else {
                    throw DevToolError(message: "Lone surrogate \\u\(String(unit, radix: 16))")
                }
            } else if marker == "x", let value = hexValue(from: i + 2, count: 2), let scalar = Unicode.Scalar(value) {
                output.append(scalar)
                i += 4
            } else {
                output.append(scalars[i])
                i += 1
            }
        }
        return DevToolResult(primary: String(output))
    }

    // MARK: Smart decode

    /// Peels off layers of URL, HTML entity, unicode escape, hex and Base64 encoding until none is left
    static func smartDecode(_ input: String) throws -> DevToolResult {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var layers: [String] = []

        while layers.count < 10, let (layer, decoded) = decodeOneLayer(text) {
            layers.append(layer)
            text = decoded
        }
        guard !layers.isEmpty else {
            throw DevToolError(message: "No encoding detected")
        }
        let count = layers.count == 1 ? "1 layer" : "\(layers.count) layers"
        return DevToolResult(primary: text, detail: "\(count): \(layers.joined(separator: " → "))")
    }

    private static func decodeOneLayer(_ text: String) -> (String, String)? {
        if matches(text, "%[0-9A-Fa-f]{2}"),
           let decoded = text.removingPercentEncoding, decoded != text {
            return ("URL", decoded)
        }
        if matches(text, "&(#[0-9]+|#[xX][0-9a-fA-F]+|amp|lt|gt|quot|apos|nbsp);") {
            let decoded = htmlDecode(text).primary
            if decoded != text { return ("HTML", decoded) }
        }
        if matches(text, #"\\u[0-9a-fA-F]{4}|\\u\{[0-9a-fA-F]+\}|\\x[0-9a-fA-F]{2}"#),
           let decoded = try? unicodeUnescape(text).primary, decoded != text {
            return ("Unicode", decoded)
        }
        if text.count >= 8, matches(text, "^[0-9a-fA-F]+$"),
           let decoded = try? hexDecode(text).primary, isReadable(decoded) {
            return ("Hex", decoded)
        }
        if text.count >= 8, matches(text, "^[A-Za-z0-9+/_-]+={0,2}$"),
           let decoded = try? DevTransforms.base64Decode(text).primary, isReadable(decoded) {
            return ("Base64", decoded)
        }
        return nil
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    /// No control characters apart from tabs and line breaks
    private static func isReadable(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { scalar in
            scalar == "\t" || scalar == "\n" || scalar == "\r"
                || !(scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value))
        }
    }
}
