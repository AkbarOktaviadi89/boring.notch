//
//  BoringNotchXPCHelperProtocol.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation

/// The protocol that this service will vend as its API. This protocol will also need to be visible to the process hosting the service.
@objc protocol BoringNotchXPCHelperProtocol {
    func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void)
    func requestAccessibilityAuthorization()
    func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void)
    // Keyboard backlight / CoreBrightness access (performed by the helper)
    func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Screen brightness access (performed by the helper)
    func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Dev servers: listening TCP sockets of the user's processes (the sandboxed app can't see them)
    func listeningSocketsReport(with reply: @escaping (String?) -> Void)
    func processDetailsReport(forPIDs pidList: String, with reply: @escaping (String?) -> Void)
    func terminateListeningProcess(_ pid: Int32, force: Bool, with reply: @escaping (Bool) -> Void)
    // System monitor: processes sorted by CPU use (the sandboxed app can't run ps on other processes)
    func topProcessesReport(with reply: @escaping (String?) -> Void)
}

