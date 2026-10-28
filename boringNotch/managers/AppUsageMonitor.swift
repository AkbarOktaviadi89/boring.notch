//
//  AppUsageMonitor.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-28.
//

import AppKit
import Combine
import Defaults

extension AppUsageSort: Defaults.Serializable {}

/// Per-app CPU, memory and energy for the Apps section of Monitor, read by the XPC helper.
/// Polls only while the section is on screen.
@MainActor
final class AppUsageMonitor: ObservableObject {
    static let shared = AppUsageMonitor()

    /// Rows shown at most; the rest are idle background processes
    static let rowLimit = 30

    @Published private(set) var apps: [AppUsage] = []
    @Published private(set) var hasLoaded = false
    @Published private(set) var helperUnavailable = false

    private var pollTask: Task<Void, Never>?
    private var viewers = 0
    private var icons: [String: NSImage] = [:]

    private init() {}

    /// Counted like SystemMonitor: the view may appear again before it disappears
    func startMonitoring() {
        viewers += 1
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                // The report itself takes a second (top needs two samples)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopMonitoring() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        guard let report = await XPCHelperClient.shared.appUsageReport() else {
            helperUnavailable = true
            hasLoaded = true
            return
        }
        let parts = report.components(separatedBy: ProcessGuard.reportSeparator)
        let processes = AppUsageStats.parseProcesses(parts[0])
        let energy = parts.count > 1 ? AppUsageStats.parseEnergy(parts[1]) : [:]
        let rows = AppUsageStats.group(processes, energy: energy, currentUID: getuid())
        apps = Array(AppUsageStats.sorted(rows, by: Defaults[.monitorAppSort]).prefix(Self.rowLimit))
        helperUnavailable = false
        hasLoaded = true
    }

    /// Re-sorts what is already loaded, so switching the sort feels instant
    func resort() {
        apps = AppUsageStats.sorted(apps, by: Defaults[.monitorAppSort])
    }

    func forceQuit(_ app: AppUsage) async -> Bool {
        guard let pid = app.quitPID else { return false }
        let done = await XPCHelperClient.shared.forceQuitProcess(pid)
        if done {
            apps.removeAll { $0.id == app.id }
        }
        return done
    }

    func icon(for app: AppUsage) -> NSImage? {
        guard let bundle = app.bundlePath else { return nil }
        if let cached = icons[bundle] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: bundle)
        icons[bundle] = icon
        return icon
    }
}
