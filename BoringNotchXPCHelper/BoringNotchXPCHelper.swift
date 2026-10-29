//
//  BoringNotchXPCHelper.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation
import CoreServices
import ApplicationServices
import IOKit
import CoreGraphics

class BoringNotchXPCHelper: NSObject, BoringNotchXPCHelperProtocol {
    
    @objc func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void) {
        reply(AXIsProcessTrusted())
    }

    @objc func requestAccessibilityAuthorization() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void) {
        if AXIsProcessTrusted() {
            reply(true)
            return
        }

        if promptIfNeeded {
            requestAccessibilityAuthorization()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            reply(AXIsProcessTrusted())
        }
    }
    
    private class KeyboardBrightnessClient {
        private static let keyboardID: UInt64 = 1
        private var clientInstance: NSObject?
        private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
        private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

        init() {
            var loaded = false
            let bundlePaths = [
                "/System/Library/PrivateFrameworks/CoreBrightness.framework",
                "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
            ]
            for path in bundlePaths where !loaded {
                if let bundle = Bundle(path: path) {
                    loaded = bundle.load()
                }
            }
            if loaded, let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
                clientInstance = cls.init()
            }
        }

        var isAvailable: Bool { clientInstance != nil }

        func currentBrightness() -> Float? {
            guard let clientInstance,
                  let fn: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
            else { return nil }
            return fn(clientInstance, getSelector, Self.keyboardID)
        }

        func setBrightness(_ value: Float) -> Bool {
            guard let clientInstance,
                  let fn: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
            else { return false }
            return fn(clientInstance, setSelector, value, Self.keyboardID).boolValue
        }

        private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
        private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool

        private func methodIMP<T>(on object: NSObject, selector: Selector, as type: T.Type) -> T? {
            guard let cls = object_getClass(object),
                  let method = class_getInstanceMethod(cls, selector)
            else { return nil }
            let imp = method_getImplementation(method)
            return unsafeBitCast(imp, to: type)
        }
    }

    private static let keyboardClient = KeyboardBrightnessClient()

    @objc func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.isAvailable)
    }

    @objc func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void) {
        reply(Self.keyboardClient.currentBrightness().map { NSNumber(value: $0) })
    }

    @objc func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.setBrightness(value))
    }
    // MARK: - Screen Brightness (moved from client app into helper)

    @objc func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        var b: Float = 0
        reply(displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) || ioServiceFor(displayID: CGMainDisplayID()) != nil)
    }

    @objc func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void) {
        var b: Float = 0
        if displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) {
            reply(NSNumber(value: b))
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            var level: Float = 0
            if IODisplayGetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess {
                IOObjectRelease(io)
                reply(NSNumber(value: level))
                return
            }
            IOObjectRelease(io)
        }
        reply(nil)
    }

    @objc func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        let clamped = max(0, min(1, value))
        if displayServicesSetBrightness(displayID: CGMainDisplayID(), value: clamped) {
            reply(true)
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            let ok = IODisplaySetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, clamped) == kIOReturnSuccess
            IOObjectRelease(io)
            reply(ok)
            return
        }
        reply(false)
    }

    // MARK: - Dev servers

    private static let lsofPath = "/usr/sbin/lsof"
    private static let listeningArguments = ["+c", "0", "-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"]

    @objc func listeningSocketsReport(with reply: @escaping (String?) -> Void) {
        reply(Self.run(Self.lsofPath, Self.listeningArguments))
    }

    /// One "pid<TAB>executable path<TAB>working directory" line per pid in the comma-separated list
    @objc func processDetailsReport(forPIDs pidList: String, with reply: @escaping (String?) -> Void) {
        let pids = pidList.split(separator: ",").compactMap { Int32($0) }
        let lines = pids.map { pid in
            "\(pid)\t\(Self.executablePath(of: pid) ?? "")\t\(Self.workingDirectory(of: pid) ?? "")"
        }
        reply(lines.joined(separator: "\n"))
    }

    /// Only signals processes of the current user that are listening on a TCP port right now,
    /// so the app can't be used to kill arbitrary processes
    @objc func terminateListeningProcess(_ pid: Int32, force: Bool, with reply: @escaping (Bool) -> Void) {
        guard pid > 1, pid != getpid(), Self.ownerUID(of: pid) == getuid(),
              let report = Self.run(Self.lsofPath, Self.listeningArguments + ["-p", String(pid)]),
              report.split(whereSeparator: \.isNewline).contains(where: { $0 == "p\(pid)" })
        else {
            reply(false)
            return
        }
        reply(kill(pid, force ? SIGKILL : SIGTERM) == 0)
    }

    // MARK: - System monitor

    @objc func topProcessesReport(with reply: @escaping (String?) -> Void) {
        reply(Self.run("/bin/ps", ["-Aceo", "pid=,pcpu=,rss=,comm=", "-r"]))
    }

    /// ps for CPU and memory with full executable paths (to group helpers under their app), then top's POWER
    /// column, the Energy Impact Activity Monitor shows. top needs two samples a second apart for it.
    @objc func appUsageReport(with reply: @escaping (String?) -> Void) {
        guard let listing = Self.run("/bin/ps", ["-Axo", "pid=,ppid=,uid=,pcpu=,rss=,comm="]) else {
            reply(nil)
            return
        }
        // Some processes rewrite their name ("redis-server *:6379"); the real executable path groups and guards them right
        let processes = listing.split(whereSeparator: \.isNewline).map { line -> String in
            let fields = line.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
            guard fields.count == 6, let pid = Int32(fields[0]), let path = Self.executablePath(of: pid) else { return String(line) }
            return fields[0..<5].joined(separator: " ") + " " + path
        }.joined(separator: "\n")
        let energy = Self.run("/usr/bin/top", ["-l", "2", "-s", "1", "-o", "power", "-n", "300", "-stats", "pid,power"]) ?? ""
        reply(processes + "\n" + ProcessGuard.reportSeparator + "\n" + energy)
    }

    /// Four reports joined by a separator line; the app's NetworkInfoParser reads them
    @objc func networkReport(with reply: @escaping (String?) -> Void) {
        let separator = "\n@@BORING-NOTCH-SECTION@@\n"
        let parts = [
            Self.run("/usr/sbin/scutil", ["--nwi"]) ?? "",
            Self.run("/usr/sbin/scutil", ["--dns"]) ?? "",
            Self.run("/sbin/route", ["-n", "get", "default"]) ?? "",
            Self.run("/usr/sbin/networksetup", ["-listallhardwareports"]) ?? "",
        ]
        reply(parts.joined(separator: separator))
    }

    /// "path<TAB>last used (seconds since 1970)<TAB>use count" per folder in the home folder used in the last `days` days
    @objc func recentFoldersReport(days: Int, with reply: @escaping (String?) -> Void) {
        let home = NSHomeDirectory()
        let query = "kMDItemContentType == \"public.folder\" && kMDItemLastUsedDate >= $time.today(-\(max(1, min(days, 365))))"
        guard let listing = Self.run("/usr/bin/mdfind", ["-onlyin", home, query]) else {
            reply(nil)
            return
        }
        let lines = listing.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let path = String(line)
            guard let item = MDItemCreate(nil, path as CFString),
                  let date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date else { return nil }
            let count = (MDItemCopyAttribute(item, "kMDItemUseCount" as CFString) as? NSNumber)?.intValue ?? 1
            return "\(path)\t\(date.timeIntervalSince1970)\t\(count)"
        }
        reply(lines.joined(separator: "\n"))
    }

    /// Shows a folder in Finder. Only existing folders: this isn't a way to open arbitrary files or apps.
    @objc func openFolder(_ path: String, with reply: @escaping (Bool) -> Void) {
        var isDirectory: ObjCBool = false
        guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue,
              !["app", "bundle", "framework"].contains((path as NSString).pathExtension.lowercased())
        else {
            reply(false)
            return
        }
        reply(Self.run("/usr/bin/open", [path]) != nil)
    }

    /// The folder screenshots are saved to, with ~ expanded; Desktop when it was never changed
    @objc func screenshotLocation(with reply: @escaping (String?) -> Void) {
        let configured = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
            ?? Self.run("/usr/bin/defaults", ["read", "com.apple.screencapture", "location"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = (configured?.isEmpty == false ? configured! : "~/Desktop") as NSString
        reply(path.expandingTildeInPath)
    }

    /// Checked here again, not only in the app: the user's own processes outside macOS's system folders
    @objc func forceQuitProcess(_ pid: Int32, with reply: @escaping (Bool) -> Void) {
        guard pid > 1, pid != getpid(),
              let uid = Self.ownerUID(of: pid),
              let path = Self.executablePath(of: pid),
              ProcessGuard.canForceQuit(path: path, uid: uid, currentUID: getuid())
        else {
            reply(false)
            return
        }
        reply(kill(pid, SIGKILL) == 0)
    }

    /// Runs a command and returns its standard output. lsof exits with 1 when nothing matches, which is not an error here.
    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // Read before waiting so a full pipe buffer can't block the child
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private static func executablePath(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func workingDirectory(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
    }

    private static func ownerUID(of pid: Int32) -> uid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info.pbi_uid
    }

    // MARK: - Private helpers for DisplayServices / IOKit access
    private func displayServicesGetBrightness(displayID: CGDirectDisplayID, out: inout Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesGetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        var tmp: Float = 0
        let r = fn(displayID, &tmp)
        if r == 0 { out = tmp; return true }
        return false
    }

    private func displayServicesSetBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(displayID, value) == 0
    }

    private func ioServiceFor(displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as NSDictionary
            if let vendorID = info[kDisplayVendorID] as? UInt32,
               let productID = info[kDisplayProductID] as? UInt32,
               vendorID == CGDisplayVendorNumber(displayID),
               productID == CGDisplayModelNumber(displayID) {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    // MARK: - Helper handle for private framework
    private enum DisplayServicesHandle {
        static let handle: UnsafeMutableRawPointer? = {
            let paths = [
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices"
            ]
            for p in paths {
                if let h = dlopen(p, RTLD_LAZY) { return h }
            }
            return nil
        }()
    }
}
