//
//  TextLayoutTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import Foundation

func runTextLayoutTests() {
    func f(_ text: String, x: Double, y: Double, h: Double = 0.04) -> RecognizedFragment {
        RecognizedFragment(text: text, x: x, y: y, width: 0.2, height: h)
    }
    // Vision's y grows upwards: 0.9 is near the top
    check("ocr top to bottom", TextLayout.join([f("second", x: 0.1, y: 0.80), f("first", x: 0.1, y: 0.85)]), "first\nsecond")
    check("ocr same line left to right", TextLayout.join([f("world", x: 0.5, y: 0.80), f("hello", x: 0.1, y: 0.805)]), "hello world")
    check("ocr paragraph gap", TextLayout.join([f("Title", x: 0.1, y: 0.90), f("Body text", x: 0.1, y: 0.70)]), "Title\n\nBody text")
    check("ocr skips blank", TextLayout.join([f("  ", x: 0.1, y: 0.9), f("only", x: 0.1, y: 0.5)]), "only")
    check("ocr empty", TextLayout.join([]), "")
    check("ocr trims pieces", TextLayout.join([f(" a ", x: 0.1, y: 0.5), f(" b", x: 0.4, y: 0.5)]), "a b")
    check("words", String(TextLayout.wordCount("satu dua\ntiga  empat")), "4")
}
