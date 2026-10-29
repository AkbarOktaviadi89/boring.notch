//
//  ClipboardDetectorTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Foundation

func runClipboardDetectorTests() {
    func kind(_ text: String) -> String {
        ClipboardDetector.detect(text).map { "\($0)" } ?? "nil"
    }

    let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjMiLCJuYW1lIjoiQWtiYXIiLCJpYXQiOjE3NjE1MjM2MTEsImV4cCI6MTc2MTUyNzIxMX0.sig"
    check("detect jwt", kind(jwt), "jwt")
    check("detect bearer jwt", kind("Bearer " + jwt), "jwt")
    check("detect json object", kind(#"{"a":1,"b":[true]}"#), "json")
    check("detect json array", kind("[1, 2, 3]"), "json")
    check("json scalar is not suggested", kind("42"), "nil")
    check("detect unix seconds", kind("1761523611"), "timestamp")
    check("detect unix millis", kind("1761523611250"), "timestamp")
    check("ten digits outside 2000-2100 is not a timestamp", kind("9999999999"), "nil")
    check("phone-like number is not a timestamp", kind("081234567890"), "nil")
    check("detect url encoded", kind("PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg%3D%3D"), "encoded")
    check("detect base64 text", kind("aGFsbyBkdW5pYSBpbmkgdGVrcyBiaWFzYQ=="), "encoded")
    check("detect html entities", kind("&lt;img src=x onerror=alert(1)&gt;"), "encoded")
    check("detect unicode escapes", kind(#"caf\u00e9 \u0041"#), "encoded")
    check("detect hex text", kind("3c7376673e3c2f7376673e"), "encoded")

    check("sha256 hash is not suggested", kind("2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"), "nil")
    check("plain sentence is not suggested", kind("halo, ini cuma teks biasa"), "nil")
    check("plain word is not suggested", kind("password"), "nil")
    check("long camelCase identifier is not suggested", kind("HelloWorldFooBarBaz"), "nil")
    check("long url is offered for shortening", kind("https://github.com/AkbarOktaviadi89/boring.notch"), "link")
    check("short url is not suggested", kind("https://github.com/x"), "nil")
    check("short link is not suggested again", kind("https://tinyurl.com/2p8abcdefghijklmnopqrstuvwxyz12"), "nil")
    check("url with encoded query is suggested", kind("https://x.test/search?q=%3Cscript%3E"), "encoded")
    check("empty is not suggested", kind("   "), "nil")
    check("huge text is not suggested", kind(String(repeating: "a", count: 200_001)), "nil")
}
