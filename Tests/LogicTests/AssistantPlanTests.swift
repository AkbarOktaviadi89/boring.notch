//
//  AssistantPlanTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-30.
//

import Foundation

func runAssistantPlanTests() {
    let long = String(repeating: "Tugas kelompok dikumpulkan hari Jumat dan presentasi di lab. ", count: 10)
    check("offer long prose", String(AssistantPlan.shouldOfferSummary(long)), "true")
    check("no offer short", String(AssistantPlan.shouldOfferSummary("Tugas dikumpulkan hari Jumat.")), "false")
    let code = String(repeating: "const a = () => { return b(); }; ", count: 20)
    check("no offer code", String(AssistantPlan.shouldOfferSummary(code)), "false")
    let numbers = String(repeating: "12 34 56 78 90 ", count: 30)
    check("no offer numbers", String(AssistantPlan.shouldOfferSummary(numbers)), "false")

    let huge = String(repeating: "word ", count: 2_000)
    let clipped = AssistantPlan.clipped(huge)
    check("clip long", String(AssistantPlan.wordCount(clipped.text)) + "/" + String(clipped.wasCut), "1500/true")
    check("clip short", String(AssistantPlan.clipped("  a b c  ").wasCut) + AssistantPlan.clipped("  a b c  ").text, "falsea b c")

    check("tidy bullets", AssistantPlan.tidy("- Tugas Jumat.\n\n- Tiga orang.\n\n•  Lab 2"), "- Tugas Jumat.\n- Tiga orang.\n- Lab 2")
    check("tidy prose", AssistantPlan.tidy("Dear Sir,\n\n\n\nThank you.\n"), "Dear Sir,\n\nThank you.")
    check("tidy star bullets", AssistantPlan.tidy("* one\n* two"), "- one\n- two")

    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    check("due date", AssistantPlan.dueDate("2026-11-07", calendar: utc).map { String(Int($0.timeIntervalSince1970)) } ?? "nil", "1794009600")
    check("due empty", AssistantPlan.dueDate("") == nil ? "nil" : "date", "nil")
    check("due nonsense", AssistantPlan.dueDate("next friday") == nil ? "nil" : "date", "nil")
    check("due bad month", AssistantPlan.dueDate("2026-13-01") == nil ? "nil" : "date", "nil")

    contains("instructions forbid guessing", AssistantAction.summarize.instructions, "never guess a date")
}
