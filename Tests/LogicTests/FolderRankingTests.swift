//
//  FolderRankingTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import Foundation

func runFolderRankingTests() {
    let home = "/Users/akbar"
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
    func worth(_ path: String) -> String { String(FolderRanking.isWorthListing(path, home: home)) }

    // Which folders
    check("folder normal", worth("/Users/akbar/Data/Joki/dpr"), "true")
    check("folder home itself", worth("/Users/akbar"), "false")
    check("folder outside home", worth("/Applications/Utilities"), "false")
    check("folder hidden", worth("/Users/akbar/.config/nvim"), "false")
    check("folder library", worth("/Users/akbar/Library/Mail"), "false")
    check("folder node modules", worth("/Users/akbar/Data/app/node_modules/react"), "false")
    check("folder inside app", worth("/Users/akbar/Applications/Foo.app/Contents"), "false")
    check("folder xcodeproj", worth("/Users/akbar/Data/x/App.xcodeproj"), "false")
    check("folder dotted name ok", worth("/Users/akbar/Data/v1.2 release"), "true")

    // Report
    let report = "/Users/akbar/Data/Joki/dpr\t1799990000\t3\n/Users/akbar/Desktop\t1799900000\t12\nbroken line\n\t1\t2\n"
    let parsed = FolderRanking.parse(report)
    check("parse rows", String(parsed.count), "2")
    check("parse count", String(parsed.first?.useCount ?? -1), "3")

    // Score: frequent and recent beats either alone
    let fresh = FolderUsage(path: "a", lastUsed: ago(0), useCount: 2)
    let old = FolderUsage(path: "b", lastUsed: ago(20), useCount: 10)
    let often = FolderUsage(path: "c", lastUsed: ago(1), useCount: 10)
    check("score often and recent wins", String(FolderRanking.score(often, now: now) > FolderRanking.score(fresh, now: now)), "true")
    check("score recent beats stale", String(FolderRanking.score(fresh, now: now) > FolderRanking.score(old, now: now)), "true")

    // Merge
    let merged = FolderRanking.merge([FolderUsage(path: "x", lastUsed: ago(5), useCount: 2)], [FolderUsage(path: "x", lastUsed: ago(1), useCount: 3)])
    check("merge sums counts", String(merged.first?.useCount ?? 0), "5")
    check("merge keeps latest", String(merged.first?.lastUsed == ago(1)), "true")

    // List
    let usage = [
        FolderUsage(path: "/Users/akbar/Data/Joki/dpr", lastUsed: ago(0), useCount: 5),
        FolderUsage(path: "/Users/akbar/Desktop", lastUsed: ago(10), useCount: 2),
        FolderUsage(path: "/Users/akbar/Data/Course/HTB", lastUsed: ago(1), useCount: 8),
        FolderUsage(path: "/Users/akbar/Library/Caches", lastUsed: ago(0), useCount: 99),
    ]
    func names(_ rows: [ListedFolder]) -> String { rows.map { ($0.isPinned ? "📌" : "") + $0.name }.joined(separator: ",") }
    check("list ranked", names(FolderRanking.list(pinned: [], usage: usage, hidden: [], home: home, now: now)), "HTB,dpr,Desktop")
    check("list pinned first", names(FolderRanking.list(pinned: ["/Users/akbar/Desktop"], usage: usage, hidden: [], home: home, now: now)), "📌Desktop,HTB,dpr")
    check("list hidden out", names(FolderRanking.list(pinned: [], usage: usage, hidden: ["/Users/akbar/Data/Course/HTB"], home: home, now: now)), "dpr,Desktop")
    check("list search", names(FolderRanking.list(pinned: [], usage: usage, hidden: [], home: home, now: now, query: "joki")), "dpr")
    check("list limit", names(FolderRanking.list(pinned: ["/Users/akbar/Desktop"], usage: usage, hidden: [], home: home, now: now, limit: 2)), "📌Desktop,HTB")

    check("parent nested", FolderRanking.displayParent(of: "/Users/akbar/Data/Joki/dpr", home: home), "~/Data/Joki")
    check("parent home", FolderRanking.displayParent(of: "/Users/akbar/Desktop", home: home), "~")
    check("parent outside", FolderRanking.displayParent(of: "/Volumes/USB/Tugas", home: home), "/Volumes/USB")
}
