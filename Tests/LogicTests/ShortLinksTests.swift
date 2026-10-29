//
//  ShortLinksTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import Foundation

func runShortLinksTests() {
    func normalized(_ text: String) -> String { ShortLinks.normalize(text)?.absoluteString ?? "nil" }

    // Normalizing
    check("normalize https", normalized(" https://example.com/a?b=1 "), "https://example.com/a?b=1")
    check("normalize bare domain", normalized("example.com/page"), "https://example.com/page")
    check("normalize subdomain", normalized("docs.github.com"), "https://docs.github.com")
    check("normalize rejects words", normalized("hello"), "nil")
    check("normalize rejects spaces", normalized("https://a.com/x y"), "nil")
    check("normalize rejects ftp", normalized("ftp://files.example.com/a"), "nil")
    check("normalize rejects localhost", normalized("http://localhost:3000/x"), "nil")
    check("normalize rejects mailto", normalized("mailto:a@b.com"), "nil")

    // Already short
    check("shortened isgd", String(ShortLinks.isShortened(URL(string: "https://is.gd/abc")!)), "true")
    check("shortened www tinyurl", String(ShortLinks.isShortened(URL(string: "https://www.tinyurl.com/abc")!)), "true")
    check("not shortened github", String(ShortLinks.isShortened(URL(string: "https://github.com")!)), "false")

    // Clipboard hint
    check("worth long link", String(ShortLinks.worthShortening("https://www.tokopedia.com/some-shop/some-product-name-123")), "true")
    check("not worth short link", String(ShortLinks.worthShortening("https://a.com/x")), "false")
    check("not worth bare domain", String(ShortLinks.worthShortening("www.tokopedia.com/some-shop/some-product-name-123")), "false")
    check("not worth sentence", String(ShortLinks.worthShortening("see https://www.tokopedia.com/some-shop/some-product")), "false")

    // Secrets
    func reason(_ text: String) -> String { ShortLinks.sensitiveReason(URL(string: text)!) ?? "nil" }
    check("sensitive token", reason("https://app.com/reset?token=abc123"), "It has a \"token\" value, which often works like a password.")
    check("sensitive case insensitive", reason("https://app.com/x?API_KEY=zz"), "It has a \"API_KEY\" value, which often works like a password.")
    check("sensitive empty value ok", reason("https://app.com/x?token="), "nil")
    check("sensitive jwt in path", reason("https://app.com/magic/eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.x"), "It contains a login token (JWT).")
    check("sensitive credentials", reason("https://user:pw@app.com/"), "It contains a username or password.")
    check("plain link fine", reason("https://shop.com/item?id=5&ref=home"), "nil")

    // Responses
    func parsed(_ body: String, _ status: Int = 200) -> String {
        switch ShortLinks.parseResponse(body, statusCode: status) {
        case .success(let url): return url.absoluteString
        case .failure(let error): return "error: " + (error.errorDescription ?? "")
        }
    }
    check("response isgd", parsed("https://is.gd/aB3xYz\n"), "https://is.gd/aB3xYz")
    check("response tinyurl", parsed("https://tinyurl.com/2p9x8k7z"), "https://tinyurl.com/2p9x8k7z")
    check("response isgd error", parsed("Error: Please enter a valid URL to shorten"), "error: Please enter a valid URL to shorten")
    check("response bare error", parsed("Error"), "error: The shortener refused this link.")
    check("response rate limited", parsed("", 429), "error: Too many links in a short time. Wait a minute and try again.")
    check("response html", parsed("<html>oops</html>", 500), "error: The shortener sent back something that isn't a link. Try again or switch services.")
    check("response browser check", parsed("<!DOCTYPE html><html lang=\"en-US\"><head><title>Just a moment...</title>", 403),
          "error: The shortener is blocking automatic requests right now (it wants a browser check).")

    // Requests
    check("request isgd", ShortLinkService.isgd.requestURL(for: "https://a.com/x?y=1&z=2")?.absoluteString ?? "nil",
          "https://is.gd/create.php?format=simple&url=https%3A%2F%2Fa.com%2Fx%3Fy%3D1%26z%3D2")
    check("request tinyurl", ShortLinkService.tinyurl.requestURL(for: "https://a.com/")?.absoluteString ?? "nil",
          "https://tinyurl.com/api-create.php?url=https%3A%2F%2Fa.com%2F")

    // History
    let a = ShortLinkRecord(original: "https://a.com/1", short: "https://is.gd/1", service: .isgd)
    let b = ShortLinkRecord(original: "https://b.com/2", short: "https://is.gd/2", service: .isgd)
    let a2 = ShortLinkRecord(original: "https://a.com/1", short: "https://is.gd/9", service: .isgd)
    let aTiny = ShortLinkRecord(original: "https://a.com/1", short: "https://tinyurl.com/1", service: .tinyurl)
    func shorts(_ list: [ShortLinkRecord]) -> String { list.map(\.short).joined(separator: ",") }
    check("history newest first", shorts(ShortLinks.addingToHistory(b, [a])), "https://is.gd/2,https://is.gd/1")
    check("history replaces same link", shorts(ShortLinks.addingToHistory(a2, [b, a])), "https://is.gd/9,https://is.gd/2")
    check("history keeps other service", shorts(ShortLinks.addingToHistory(aTiny, [a])), "https://tinyurl.com/1,https://is.gd/1")
    let many = (0..<25).map { ShortLinkRecord(original: "https://x.com/\($0)", short: "s\($0)", service: .isgd) }
    check("history limit", String(many.reduce([]) { ShortLinks.addingToHistory($1, $0) }.count), "20")
}
