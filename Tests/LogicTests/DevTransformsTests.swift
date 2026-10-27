//
//  DevTransformsTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Foundation

func runDevTransformsTests() {
    let utc = TimeZone(identifier: "UTC")!
    let jakarta = TimeZone(identifier: "Asia/Jakarta")!

    // JSON
    check("json format", try? DevTransforms.formatJSON(#"{"b":1,"a":[true,null,"x/y"]}"#).primary,
          "{\n  \"a\" : [\n    true,\n    null,\n    \"x/y\"\n  ],\n  \"b\" : 1\n}")
    check("json minify", try? DevTransforms.minifyJSON("{\n  \"a\" : 1,\n  \"b\" : [1, 2]\n}").primary, #"{"a":1,"b":[1,2]}"#)
    check("json fragment", try? DevTransforms.minifyJSON(" \"hi\" ").primary, #""hi""#)
    checkThrows("json invalid") { try DevTransforms.formatJSON("{a:1}") }
    checkThrows("json empty") { try DevTransforms.formatJSON("   ") }

    // Base64
    check("b64 encode", DevTransforms.base64Encode("halo dunia ✓").primary, "aGFsbyBkdW5pYSDinJM=")
    check("b64 decode", try? DevTransforms.base64Decode("aGFsbyBkdW5pYSDinJM=").primary, "halo dunia ✓")
    check("b64 decode no padding + whitespace", try? DevTransforms.base64Decode("  aGFsbw\n ").primary, "halo")
    checkThrows("b64 decode binary") { try DevTransforms.base64Decode("P_8-") }
    checkThrows("b64 decode garbage") { try DevTransforms.base64Decode("@@@") }
    check("b64 decode url-safe text", try? DevTransforms.base64Decode("PDw_Pz4-").primary, "<<??>>")

    // URL
    check("url encode", DevTransforms.urlEncode("a b&c=d/é?").primary, "a%20b%26c%3Dd%2F%C3%A9%3F")
    check("url decode", try? DevTransforms.urlDecode("a%20b+c%26%C3%A9").primary, "a b c&é")
    checkThrows("url decode invalid") { try DevTransforms.urlDecode("%E0%A4%A") }

    // UUID
    let id = DevTransforms.uuid(uppercase: false).primary
    check("uuid lowercase format", id.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}$", options: .regularExpression) != nil ? "ok" : id, "ok")
    let upper = DevTransforms.uuid(uppercase: true).primary
    check("uuid uppercase", upper == upper.uppercased() && upper != upper.lowercased() ? "ok" : upper, "ok")

    // Timestamp -> date
    check("ts seconds", try? DevTransforms.convertTimestamp("1761523611", timeZone: jakarta).primary, "2025-10-27 07:06:51 GMT+7")
    check("ts seconds detail", try? DevTransforms.convertTimestamp("1761523611", timeZone: jakarta).detail, "2025-10-27T00:06:51Z")
    check("ts millis", try? DevTransforms.convertTimestamp("1761523611250", timeZone: utc).primary, "2025-10-27 00:06:51 GMT")
    // Date -> timestamp
    check("date iso", try? DevTransforms.convertTimestamp("2025-10-27T00:06:51Z", timeZone: jakarta).primary, "1761523611")
    check("date iso millis detail", try? DevTransforms.convertTimestamp("2025-10-27T00:06:51.250Z", timeZone: utc).detail, "1761523611250 ms")
    check("date local", try? DevTransforms.convertTimestamp("2025-10-27 07:06:51", timeZone: jakarta).primary, "1761523611")
    check("date only", try? DevTransforms.convertTimestamp("2025-10-27", timeZone: utc).primary, "1761523200")
    checkThrows("ts invalid") { try DevTransforms.convertTimestamp("kemarin", timeZone: utc) }

    // Color
    check("hex", DevTransforms.color(red: 1, green: 0.5, blue: 0).primary, "#FF8000")
    check("rgb", DevTransforms.color(red: 1, green: 0.5, blue: 0).detail, "rgb(255, 128, 0)")
}
