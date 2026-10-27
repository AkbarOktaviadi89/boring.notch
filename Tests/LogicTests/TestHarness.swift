//
//  TestHarness.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Foundation

var passes = 0
var failures = 0

func check(_ name: String, _ actual: String?, _ expected: String?) {
    if actual == expected {
        passes += 1
    } else {
        failures += 1
        print("FAIL \(name)\n  expected: \(String(reflecting: expected))\n  actual:   \(String(reflecting: actual))")
    }
}

func checkThrows(_ name: String, _ block: () throws -> Any) {
    do {
        _ = try block()
        failures += 1
        print("FAIL \(name): expected an error")
    } catch {
        passes += 1
    }
}

func contains(_ name: String, _ haystack: String?, _ needle: String) {
    check(name, (haystack?.contains(needle) ?? false) ? "contains" : haystack, "contains")
}
