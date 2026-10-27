//
//  DevServerMonitor.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import AppKit
import Combine

@MainActor
final class DevServerMonitor: ObservableObject {
    static let shared = DevServerMonitor()

    @Published private(set) var processes: [ListeningProcess] = []
    @Published private(set) var hasLoaded = false
    @Published private(set) var helperUnavailable = false
    /// Processes that got SIGTERM; offered a force quit if they are still listening
    @Published private(set) var stopping: Set<Int32> = []

    private var pollTask: Task<Void, Never>?
    private var viewers = 0

    private init() {}

    // MARK: - Polling while the tab is visible

    /// Counted like NotchKeyboardFocus: the tab may appear again before it disappears
    func startMonitoring() {
        viewers += 1
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(3))
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
        guard let report = await XPCHelperClient.shared.listeningSocketsReport() else {
            helperUnavailable = true
            hasLoaded = true
            return
        }
        let listening = DevServerParser.parseListening(report)
        let detailsReport = await XPCHelperClient.shared.processDetailsReport(forPIDs: listening.map(\.pid)) ?? ""
        processes = DevServerParser.merge(listening, details: DevServerParser.parseDetails(detailsReport))
        stopping.formIntersection(processes.map(\.pid))
        helperUnavailable = false
        hasLoaded = true
    }

    // MARK: - Actions

    func open(port: Int) {
        guard let url = URL(string: "http://localhost:\(port)") else { return }
        NSWorkspace.shared.open(url)
    }

    func copyURL(port: Int) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("http://localhost:\(port)", forType: .string)
    }

    /// First press asks the process to quit (SIGTERM); if it is still listening, the next press forces it (SIGKILL)
    func stop(_ process: ListeningProcess) async {
        let force = stopping.contains(process.pid)
        guard await XPCHelperClient.shared.terminateListeningProcess(process.pid, force: force) else { return }
        stopping.insert(process.pid)
        try? await Task.sleep(for: .milliseconds(600))
        await refresh()
    }
}
