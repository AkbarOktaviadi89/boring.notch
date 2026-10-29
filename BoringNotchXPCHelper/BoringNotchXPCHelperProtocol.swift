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
    // Apps monitor: every process with its CPU, memory and energy, then a force quit guarded by ProcessGuard
    func appUsageReport(with reply: @escaping (String?) -> Void)
    func forceQuitProcess(_ pid: Int32, with reply: @escaping (Bool) -> Void)
    // Network monitor: interfaces, DNS, gateway and hardware port names (scutil and friends, outside the sandbox)
    func networkReport(with reply: @escaping (String?) -> Void)
    // Folders panel: folders Finder opened lately (Spotlight's last-used date and use count), and opening one in Finder
    func recentFoldersReport(days: Int, with reply: @escaping (String?) -> Void)
    func openFolder(_ path: String, with reply: @escaping (Bool) -> Void)
}

/*
 To use the service from an application or other process, use NSXPCConnection to establish a connection to the service by doing something like this:

     connectionToService = NSXPCConnection(serviceName: "theboringteam.boringnotch.BoringNotchXPCHelper")
     connectionToService.remoteObjectInterface = NSXPCInterface(with: (any BoringNotchXPCHelperProtocol).self)
     connectionToService.resume()

 Once you have a connection to the service, you can use it like this:

     if let proxy = connectionToService.remoteObjectProxy as? BoringNotchXPCHelperProtocol {
         proxy.performCalculation(firstNumber: 23, secondNumber: 19) { result in
             NSLog("Result of calculation is: \(result)")
         }
     }

 And, when you are finished with the service, clean up the connection like this:

     connectionToService.invalidate()
*/
