//
//  main.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

// Tests for the Foundation-only logic files in boringNotch/helpers.
// They run without Xcode's test runner or the app: `make test` compiles them together with those files.

import Foundation

runDevTransformsTests()
runSecurityTests()
runDevServerTests()
runSystemStatsTests()
runClipboardDetectorTests()
runStudyStatsTests()
runFlashcardsTests()
runSecurityToolsTests()
runMonthGridTests()
runTodoScheduleTests()
runTodoReminderTests()
runNotesTests()

print(failures == 0 ? "All \(passes) tests passed" : "\(failures) of \(passes + failures) tests FAILED")
exit(failures == 0 ? 0 : 1)
