//
//  SystemMonitor.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Combine
import Foundation

@MainActor
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    static let historyLength = 60

    /// 0...1, nil until two samples exist
    @Published private(set) var cpuUsage: Double?
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryUsed: UInt64 = 0
    @Published private(set) var memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    @Published private(set) var downloadRate: Double?
    @Published private(set) var uploadRate: Double?
    @Published private(set) var diskFree: UInt64?
    @Published private(set) var diskTotal: UInt64?
    @Published private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    @Published private(set) var topProcesses: [TopProcess] = []

    private var previousTicks: [CPUTicks]?
    private var previousNetwork: [String: (received: UInt64, sent: UInt64)] = [:]
    private var previousSampleDate: Date?
    private var pollTask: Task<Void, Never>?
    private var viewers = 0
    private var tick = 0

    private init() {}

    // MARK: - Polling while the tab is visible

    /// Counted: the view may appear again before it disappears
    func startMonitoring() {
        viewers += 1
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sample()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopMonitoring() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        pollTask?.cancel()
        pollTask = nil
        // Rates need two consecutive samples; start fresh next time
        previousTicks = nil
        previousNetwork = [:]
        previousSampleDate = nil
    }

    private func sample() async {
        let now = Date()
        let seconds = previousSampleDate.map { now.timeIntervalSince($0) } ?? 0

        if let ticks = SystemSampler.cpuTicks() {
            if let previousTicks, let usage = SystemStats.cpuUsage(previous: previousTicks, current: ticks) {
                cpuUsage = usage
                cpuHistory.append(usage)
                if cpuHistory.count > Self.historyLength {
                    cpuHistory.removeFirst(cpuHistory.count - Self.historyLength)
                }
            }
            previousTicks = ticks
        }

        if let memory = SystemSampler.memory() {
            memoryUsed = memory.used
            memoryTotal = memory.total
        }

        let network = SystemSampler.networkCounters()
        if seconds > 0, !previousNetwork.isEmpty {
            var down = 0.0
            var up = 0.0
            // Per interface, so the 32-bit wrap of one counter is handled on its own
            for (name, counters) in network {
                guard let previous = previousNetwork[name] else { continue }
                down += SystemStats.rate(previous: previous.received, current: counters.received, seconds: seconds) ?? 0
                up += SystemStats.rate(previous: previous.sent, current: counters.sent, seconds: seconds) ?? 0
            }
            downloadRate = down
            uploadRate = up
        }
        previousNetwork = network
        previousSampleDate = now

        thermalState = ProcessInfo.processInfo.thermalState

        // Disk space and processes change slowly and cost more to read
        if tick % 3 == 0 {
            if let disk = SystemSampler.disk() {
                diskFree = disk.free
                diskTotal = disk.total
            }
            if let report = await XPCHelperClient.shared.topProcessesReport() {
                topProcesses = SystemStats.parseTopProcesses(report, limit: 5)
            }
        }
        tick += 1
    }
}
