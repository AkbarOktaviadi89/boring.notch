//
//  SystemStats.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Foundation

/// Cumulative CPU ticks of one core, as reported by host_processor_info
struct CPUTicks: Equatable {
    var user: UInt32
    var system: UInt32
    var idle: UInt32
    var nice: UInt32
}

struct TopProcess: Identifiable, Equatable {
    let pid: Int32
    let cpuPercent: Double
    let memoryBytes: UInt64
    let name: String

    var id: Int32 { pid }
}

/// Pure math and parsing behind the System monitor. Foundation only, so it can be tested without the app.
enum SystemStats {
    /// Share of time all cores were busy between two samples, 0...1. Nil when it can't be computed.
    static func cpuUsage(previous: [CPUTicks], current: [CPUTicks]) -> Double? {
        guard previous.count == current.count, !current.isEmpty else { return nil }
        var busy: UInt64 = 0
        var total: UInt64 = 0
        for (old, new) in zip(previous, current) {
            // Tick counters are 32-bit and wrap, so subtract with wrapping
            let user = UInt64(new.user &- old.user)
            let system = UInt64(new.system &- old.system)
            let nice = UInt64(new.nice &- old.nice)
            let idle = UInt64(new.idle &- old.idle)
            busy += user + system + nice
            total += user + system + nice + idle
        }
        guard total > 0 else { return nil }
        return Double(busy) / Double(total)
    }

    /// "Memory Used" the way Activity Monitor counts it: app memory + wired + compressed
    static func memoryUsed(internalPages: UInt64, purgeablePages: UInt64, wiredPages: UInt64, compressedPages: UInt64, pageSize: UInt64) -> UInt64 {
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        return (appPages + wiredPages + compressedPages) * pageSize
    }

    /// Bytes per second between two readings of a 32-bit interface counter
    static func rate(previous: UInt64, current: UInt64, seconds: Double) -> Double? {
        guard seconds > 0 else { return nil }
        let delta = current >= previous ? current - previous : (UInt64(UInt32.max) - previous) + current + 1
        return Double(delta) / seconds
    }

    /// "512 B", "1.2 MB", "16 GB": one decimal below 10, none above
    static func formatBytes(_ bytes: UInt64, base: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = Double(bytes)
        var unit = 0
        while value >= base, unit < units.count - 1 {
            value /= base
            unit += 1
        }
        if unit == 0 { return "\(bytes) B" }
        var number = value < 10 ? String(format: "%.1f", value) : String(format: "%.0f", value)
        if number.hasSuffix(".0") { number.removeLast(2) }
        return "\(number) \(units[unit])"
    }

    static func formatRate(_ bytesPerSecond: Double) -> String {
        formatBytes(UInt64(max(0, bytesPerSecond)), base: 1000) + "/s"
    }

    /// Parses `ps -Aceo pid=,pcpu=,rss=,comm= -r`; rss is in kilobytes
    static func parseTopProcesses(_ output: String, limit: Int) -> [TopProcess] {
        var processes: [TopProcess] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4,
                  let pid = Int32(fields[0]),
                  let cpu = Double(fields[1]),
                  let rss = UInt64(fields[2])
            else { continue }
            processes.append(TopProcess(pid: pid, cpuPercent: cpu, memoryBytes: rss * 1024, name: String(fields[3])))
            if processes.count == limit { break }
        }
        return processes
    }
}
