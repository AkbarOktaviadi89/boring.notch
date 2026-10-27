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

    // MARK: Regex

    /// All matches, one per line; the detail lists capture groups per match
    static func regexMatches(pattern: String, in text: String) throws -> DevToolResult {
        guard !pattern.isEmpty else { throw DevToolError(message: "Enter a pattern") }
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern)
        } catch {
            throw DevToolError(message: "Invalid regex")
        }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { throw DevToolError(message: "No matches") }

        let values = matches.compactMap { Range($0.range, in: text).map { String(text[$0]) } }
        var detail = matches.count == 1 ? "1 match" : "\(matches.count) matches"
        if regex.numberOfCaptureGroups > 0 {
            let groups = matches.prefix(20).map { match in
                let captured = (1...regex.numberOfCaptureGroups).map { index in
                    Range(match.range(at: index), in: text).map { String(text[$0]) } ?? "–"
                }
                return "[\(captured.joined(separator: ", "))]"
            }
            detail += " · groups: " + groups.joined(separator: " ")
        }
        return DevToolResult(primary: values.joined(separator: "\n"), detail: detail)
    }

    // MARK: Diff

    /// Larger inputs are cut so the O(n·m) table stays small
    static let diffLineLimit = 2000

    /// Line diff: "  " unchanged, "- " only in the first text, "+ " only in the second
    static func lineDiff(_ first: String, _ second: String) -> DevToolResult {
        let a = Array(diffLines(first).prefix(diffLineLimit))
        let b = Array(diffLines(second).prefix(diffLineLimit))

        // lcs[i][j]: longest common subsequence of a[i...] and b[j...]
        var lcs = [[Int32]](repeating: [Int32](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }

        var output: [String] = []
        var added = 0
        var removed = 0
        var i = 0
        var j = 0
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] {
                output.append("  " + a[i])
                i += 1
                j += 1
            } else if j >= b.count || (i < a.count && lcs[i + 1][j] >= lcs[i][j + 1]) {
                output.append("- " + a[i])
                removed += 1
                i += 1
            } else {
                output.append("+ " + b[j])
                added += 1
                j += 1
            }
        }
        let summary = added == 0 && removed == 0 ? "No differences" : "\(added) added, \(removed) removed"
        return DevToolResult(primary: output.joined(separator: "\n"), detail: summary)
    }

    private static func diffLines(_ text: String) -> [String] {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if lines.count > 1, lines.last == "" { lines.removeLast() }
        return lines
    }

    // MARK: IPv4 / CIDR

    /// "192.168.1.10/24" or a plain address (treated as /32)
    static func cidr(_ input: String) throws -> DevToolResult {
        let parts = input.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let address = ipv4(String(parts[0])) else {
            throw DevToolError(message: "Not an IPv4 address or CIDR like 192.168.1.0/24")
        }
        let prefix: Int
        if parts.count == 2 {
            guard let value = Int(parts[1]), (0...32).contains(value) else {
                throw DevToolError(message: "Prefix must be between /0 and /32")
            }
            prefix = value
        } else {
            prefix = 32
        }

        let mask: UInt32 = prefix == 0 ? 0 : UInt32.max << UInt32(32 - prefix)
        let network = address & mask
        let broadcast = network | ~mask
        let size = UInt64(1) << UInt64(32 - prefix)

        var lines = ["Netmask: \(format(mask)) (wildcard \(format(~mask)))"]
        switch prefix {
        case 32:
            lines.append("Hosts: \(format(network)) (1 address)")
        case 31:
            lines.append("Hosts: \(format(network)) – \(format(broadcast)) (2 usable, point-to-point)")
        default:
            lines.append("Hosts: \(format(network + 1)) – \(format(broadcast - 1)) (\(size - 2) usable)")
            lines.append("Broadcast: \(format(broadcast))")
        }
        lines.append("Type: \(addressType(address))")
        return DevToolResult(primary: "\(format(network))/\(prefix)", detail: lines.joined(separator: "\n"))
    }

    private static func ipv4(_ text: String) -> UInt32? {
        let octets = text.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return nil }
        var value: UInt32 = 0
        for octet in octets {
            guard !octet.isEmpty, octet.count <= 3, octet.allSatisfy(\.isASCII), octet.allSatisfy(\.isNumber),
                  let number = UInt32(octet), number <= 255
            else { return nil }
            value = value << 8 | number
        }
        return value
    }

    private static func format(_ address: UInt32) -> String {
        [24, 16, 8, 0].map { String((address >> UInt32($0)) & 0xFF) }.joined(separator: ".")
    }

    /// Ranges worth knowing when testing for SSRF or exposed services
    private static func addressType(_ address: UInt32) -> String {
        func inRange(_ base: String, _ prefix: UInt32) -> Bool {
            guard let base = ipv4(base) else { return false }
            let mask: UInt32 = prefix == 0 ? 0 : UInt32.max << (32 - prefix)
            return address & mask == base & mask
        }
        if inRange("10.0.0.0", 8) || inRange("172.16.0.0", 12) || inRange("192.168.0.0", 16) { return "Private (RFC 1918)" }
        if inRange("127.0.0.0", 8) { return "Loopback" }
        if inRange("169.254.0.0", 16) { return "Link-local (cloud metadata range)" }
        if inRange("100.64.0.0", 10) { return "Carrier-grade NAT (RFC 6598)" }
        if inRange("0.0.0.0", 8) { return "\"This\" network" }
        if inRange("224.0.0.0", 4) { return "Multicast" }
        if inRange("240.0.0.0", 4) { return "Reserved" }
        return "Public"
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
