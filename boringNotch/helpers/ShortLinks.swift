//
//  ShortLinks.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import Foundation

/// Free shorteners that need no account or API key
enum ShortLinkService: String, CaseIterable, Identifiable, Codable {
    case isgd = "is.gd"
    case tinyurl = "TinyURL"

    var id: Self { self }

    /// The plain-text API: the response body is the short link itself
    func requestURL(for longURL: String) -> URL? {
        let encoded = ShortLinks.queryEncoded(longURL)
        switch self {
        case .isgd: return URL(string: "https://is.gd/create.php?format=simple&url=\(encoded)")
        case .tinyurl: return URL(string: "https://tinyurl.com/api-create.php?url=\(encoded)")
        }
    }
}

struct ShortLinkRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    let original: String
    let short: String
    let service: ShortLinkService
    var createdAt = Date()
}

enum ShortLinkError: LocalizedError, Equatable {
    case notALink
    case alreadyShort
    case rejected(String)
    /// The service answered with a "checking your browser" page instead of its API
    case blocked
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .notALink: return "That isn't a web link. Links start with http:// or https://."
        case .alreadyShort: return "That's already a short link."
        case .rejected(let reason): return reason
        case .blocked: return "The shortener is blocking automatic requests right now (it wants a browser check)."
        case .unexpectedResponse: return "The shortener sent back something that isn't a link. Try again or switch services."
        }
    }
}

/// Link checks and the shorteners' responses. Foundation only, so it can be tested without the app.
enum ShortLinks {
    /// Links shorter than this are left alone by the clipboard hint
    static let minimumHintLength = 40
    static let historyLimit = 20

    private static let shortenerHosts: Set<String> = [
        "is.gd", "v.gd", "tinyurl.com", "bit.ly", "t.co", "goo.gl", "ow.ly", "buff.ly", "rebrand.ly", "cutt.ly", "s.id", "shorturl.at",
    ]

    /// Query names that usually carry a secret: a short link to them hands the secret to anyone who has it
    private static let sensitiveNames: Set<String> = [
        "token", "access_token", "refresh_token", "id_token", "auth", "authorization", "key", "apikey", "api_key",
        "secret", "client_secret", "password", "pass", "pwd", "sig", "signature", "session", "sessionid", "sid",
        "code", "otp", "reset", "jwt", "x-amz-signature", "x-amz-credential",
    ]

    /// A web link from typed or pasted text. "example.com/page" gets https:// added.
    static func normalize(_ text: String) -> URL? {
        var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, !candidate.contains(where: \.isWhitespace) else { return nil }
        if !candidate.contains("://") {
            // Only bare domains, so "hello" or "a.b" typos don't turn into links
            guard candidate.range(of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}([/?#:].*)?$"#, options: .regularExpression) != nil else {
                return nil
            }
            candidate = "https://" + candidate
        }
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, host.contains(".")
        else { return nil }
        return url
    }

    static func isShortened(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return shortenerHosts.contains(bare)
    }

    /// For the clipboard hint: one long http(s) link that isn't short already
    static func worthShortening(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumHintLength,
              trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://"),
              let url = normalize(trimmed)
        else { return false }
        return !isShortened(url)
    }

    /// Why this link shouldn't go to a public shortener, or nil when it looks fine
    static func sensitiveReason(_ url: URL) -> String? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let item = items.first(where: { sensitiveNames.contains($0.name.lowercased()) && !($0.value ?? "").isEmpty }) {
            return "It has a \"\(item.name)\" value, which often works like a password."
        }
        let text = url.absoluteString
        if text.range(of: #"eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}"#, options: .regularExpression) != nil {
            return "It contains a login token (JWT)."
        }
        if url.user != nil || url.password != nil {
            return "It contains a username or password."
        }
        return nil
    }

    /// The shortener's reply: the short link, or the reason it refused
    static func parseResponse(_ body: String, statusCode: Int) -> Result<URL, ShortLinkError> {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("error") {
            let reason = trimmed.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces)
            return .failure(.rejected(reason.isEmpty ? "The shortener refused this link." : reason))
        }
        let lowered = trimmed.prefix(512).lowercased()
        if lowered.hasPrefix("<!doctype html") || lowered.hasPrefix("<html"), statusCode == 403 || statusCode == 503 || lowered.contains("just a moment") {
            return .failure(.blocked)
        }
        guard (200..<300).contains(statusCode),
              let url = URL(string: trimmed), let scheme = url.scheme, scheme.hasPrefix("http"), url.host != nil
        else {
            return .failure(statusCode == 429 ? .rejected("Too many links in a short time. Wait a minute and try again.") : .unexpectedResponse)
        }
        return .success(url)
    }

    /// Percent-encodes everything but unreserved characters, so a link survives as one query value
    static func queryEncoded(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    /// Newest first, one entry per link and service, at most `historyLimit`
    static func addingToHistory(_ record: ShortLinkRecord, _ history: [ShortLinkRecord]) -> [ShortLinkRecord] {
        let rest = history.filter { !($0.original == record.original && $0.service == record.service) }
        return Array(([record] + rest).prefix(historyLimit))
    }
}
