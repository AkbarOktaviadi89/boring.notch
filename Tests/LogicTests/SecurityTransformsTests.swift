//
//  SecurityTransformsTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Foundation

func runSecurityTests() {
    let jakarta = TimeZone(identifier: "Asia/Jakarta")!
    let later = Date(timeIntervalSince1970: 1_800_000_000)

    // URL double encoding
    check("url encode twice", DevTransforms.urlEncode(DevTransforms.urlEncode("a b/").primary).primary, "a%2520b%252F")

    // JWT
    let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjMiLCJuYW1lIjoiQWtiYXIiLCJpYXQiOjE3NjE1MjM2MTEsImV4cCI6MTc2MTUyNzIxMX0.sig"
    let decoded = try? SecurityTransforms.decodeJWT(jwt, now: later, timeZone: jakarta)
    check("jwt payload", decoded?.primary, "{\n  \"exp\" : 1761527211,\n  \"iat\" : 1761523611,\n  \"name\" : \"Akbar\",\n  \"sub\" : \"123\"\n}")
    contains("jwt header", decoded?.detail, #"Header: {"alg":"HS256","typ":"JWT"}"#)
    contains("jwt exp", decoded?.detail, "exp: 2025-10-27 08:06:51 GMT+7 (expired)")
    contains("jwt iat", decoded?.detail, "iat: 2025-10-27 07:06:51 GMT+7")
    contains("jwt not verified", decoded?.detail, "Signature not verified")
    let early = try? SecurityTransforms.decodeJWT(jwt, now: Date(timeIntervalSince1970: 1_761_523_700), timeZone: jakarta)
    contains("jwt still valid", early?.detail, "(valid for 58 min)")
    let none = "eyJhbGciOiJub25lIn0.eyJzdWIiOiIxMjMiLCJuYW1lIjoiQWtiYXIiLCJpYXQiOjE3NjE1MjM2MTEsImV4cCI6MTc2MTUyNzIxMX0."
    contains("jwt alg none", (try? SecurityTransforms.decodeJWT(none, now: later, timeZone: jakarta))?.detail, "alg is \"none\"")
    contains("jwt with Bearer prefix", (try? SecurityTransforms.decodeJWT("Bearer " + jwt, now: later, timeZone: jakarta))?.primary, "\"Akbar\"")
    checkThrows("jwt invalid") { try SecurityTransforms.decodeJWT("abc.def", now: later, timeZone: jakarta) }

    // Hashes
    check("md5", SecurityTransforms.hash("hello", .md5).primary, "5d41402abc4b2a76b9719d911017c592")
    check("sha1", SecurityTransforms.hash("hello", .sha1).primary, "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d")
    check("sha256", SecurityTransforms.hash("hello", .sha256).primary, "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    check("sha512 prefix", String(SecurityTransforms.hash("hello", .sha512).primary.prefix(32)), "9b71d224bd62f3785d96d46ad3ea3d73")

    // Hex
    check("hex encode", SecurityTransforms.hexEncode("hello").primary, "68656c6c6f")
    check("hex decode spaced", try? SecurityTransforms.hexDecode("68 65 6c 6c 6f").primary, "hello")
    check("hex decode 0x", try? SecurityTransforms.hexDecode("0x68656C6C6F").primary, "hello")
    check("hex decode \\x", try? SecurityTransforms.hexDecode(#"\x68\x65\x6c\x6c\x6f"#).primary, "hello")
    check("hex decode colons", try? SecurityTransforms.hexDecode("68:65:6c:6c:6f").primary, "hello")
    checkThrows("hex decode odd") { try SecurityTransforms.hexDecode("686") }
    checkThrows("hex decode non-hex") { try SecurityTransforms.hexDecode("zz") }

    // HTML entities
    check("html encode", SecurityTransforms.htmlEncode(#"<a href="x">'&'</a>"#).primary, "&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;")
    check("html decode", SecurityTransforms.htmlDecode("&lt;b&gt;&#65;&#x42;&amp;&quot;&apos;&nbsp;&unknown;").primary, "<b>AB&\"'\u{00A0}&unknown;")

    // Unicode escapes
    check("unicode escape", SecurityTransforms.unicodeEscape("caf\u{e9} \u{1F600}").primary, #"caf\u00e9 \ud83d\ude00"#)
    check("unicode unescape", try? SecurityTransforms.unicodeUnescape(#"caf\u00e9 \ud83d\ude00 \u{1F600} \x41"#).primary, "caf\u{e9} \u{1F600} \u{1F600} A")
    checkThrows("unicode unescape lone surrogate") { try SecurityTransforms.unicodeUnescape(#"\ud83d"#) }

    // Smart decode
    let smart = try? SecurityTransforms.smartDecode("PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg%3D%3D")
    check("smart url+base64", smart?.primary, "<script>alert(1)</script>")
    check("smart url+base64 layers", smart?.detail, "2 layers: URL → Base64")
    check("smart html+unicode", try? SecurityTransforms.smartDecode(#"&lt;img src=x onerror=\u0061lert(1)&gt;"#).primary, "<img src=x onerror=alert(1)>")
    check("smart hex", try? SecurityTransforms.smartDecode("3c7376673e").primary, "<svg>")
    checkThrows("smart plain text") { try SecurityTransforms.smartDecode("hello world") }
    checkThrows("smart word that is valid base64 chars") { try SecurityTransforms.smartDecode("password") }
}
