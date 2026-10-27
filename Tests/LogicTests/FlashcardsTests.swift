//
//  FlashcardsTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Foundation

func runFlashcardsTests() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86_400

    let fresh = Flashcard(front: "SQLi", back: "' OR 1=1--", createdAt: now)
    check("new card is due", String(fresh.isDue(at: now)), "true")
    check("new card box", String(fresh.box), "0")

    let good1 = Leitner.review(fresh, remembered: true, at: now)
    check("good moves to box 1", String(good1.box), "1")
    check("box 1 due in a day", String(good1.due.timeIntervalSince(now)), String(day))
    check("not due right after review", String(good1.isDue(at: now)), "false")
    let good2 = Leitner.review(good1, remembered: true, at: now)
    check("box 2 due in 3 days", String(good2.due.timeIntervalSince(now)), String(3 * day))
    var top = good2
    for _ in 0..<5 { top = Leitner.review(top, remembered: true, at: now) }
    check("box stops at 5", String(top.box), "5")
    check("box 5 due in 30 days", String(top.due.timeIntervalSince(now)), String(30 * day))
    let again = Leitner.review(top, remembered: false, at: now)
    check("again resets to box 1", String(again.box), "1")
    check("again due in 10 minutes", String(again.due.timeIntervalSince(now)), "600.0")

    let later = Flashcard(front: "b", back: "b", createdAt: now)
    var early = Flashcard(front: "a", back: "a", createdAt: now)
    early.due = now.addingTimeInterval(-60)
    var future = Flashcard(front: "c", back: "c", createdAt: now)
    future.due = now.addingTimeInterval(60)
    check("due cards sorted, future skipped", Leitner.dueCards([later, future, early], at: now).map(\.front).joined(), "ab")

    let bulk = Leitner.parseBulk("SQLi :: ' OR 1=1--\nXSS::<script>\n\nbad line\n  a ::  b  \n:: empty front")
    check("bulk count", String(bulk.count), "3")
    check("bulk pairs", bulk.map { "\($0.front)=\($0.back)" }.joined(separator: "|"), "SQLi=' OR 1=1--|XSS=<script>|a=b")
    check("bulk keeps :: inside the back", Leitner.parseBulk("sep :: a :: b").first?.back, "a :: b")
}
