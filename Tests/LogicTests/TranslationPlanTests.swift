//
//  TranslationPlanTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import Foundation

func runTranslationPlanTests() {
    func way(_ code: String?) -> String {
        let plan = TranslationPlan.direction(detected: code)
        return plan.source + ">" + plan.target
    }
    check("indonesian to english", way("id"), "id>en")
    check("english to indonesian", way("en"), "en>id")
    check("other to indonesian", way("ja"), "en>id")
    check("unknown to indonesian", way(nil), "en>id")

    func prose(_ text: String) -> String { String(TranslationPlan.looksLikeProse(text)) }
    check("prose sentence", prose("The build failed because the certificate expired."), "true")
    check("prose indonesian", prose("Tugas ini dikumpulkan paling lambat hari Jumat."), "true")
    check("prose too short", prose("hello world"), "false")
    check("prose numbers", prose("12 34 56 78 90"), "false")
    check("prose code", prose("const user = await fetch(url);"), "false")
    check("prose swift", prose("func run() { print(1) }"), "false")
    check("prose link", prose("see https://a.com now"), "false")
    check("prose json", prose(#"{"a": "b c d"}"#), "false")
    check("prose huge", prose(String(repeating: "word ", count: 2000)), "false")

    check("offer english", String(TranslationPlan.shouldOffer("The meeting moved to Thursday afternoon.", detected: "en")), "true")
    check("no offer indonesian", String(TranslationPlan.shouldOffer("Rapatnya pindah ke Kamis sore.", detected: "id")), "false")
    check("no offer undetected", String(TranslationPlan.shouldOffer("The meeting moved to Thursday.", detected: nil)), "false")
}
