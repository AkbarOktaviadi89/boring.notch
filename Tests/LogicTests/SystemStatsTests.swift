//
//  SystemStatsTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Foundation

func runSystemStatsTests() {
    // CPU usage from tick deltas, summed over cores
    let before = [CPUTicks(user: 100, system: 50, idle: 800, nice: 50), CPUTicks(user: 0, system: 0, idle: 1000, nice: 0)]
    let after = [CPUTicks(user: 150, system: 75, idle: 850, nice: 50), CPUTicks(user: 50, system: 0, idle: 1050, nice: 0)]
    check("cpu usage", SystemStats.cpuUsage(previous: before, current: after).map { String(format: "%.3f", $0) }, "0.556")
    check("cpu usage with no time passed", SystemStats.cpuUsage(previous: after, current: after).map { String($0) } ?? "nil", "nil")
    check("cpu usage core count changed", SystemStats.cpuUsage(previous: before, current: [after[0]]).map { String($0) } ?? "nil", "nil")

    // Memory used like Activity Monitor: app memory + wired + compressed
    let memory = SystemStats.memoryUsed(internalPages: 600_000, purgeablePages: 100_000, wiredPages: 150_000, compressedPages: 50_000, pageSize: 16_384)
    check("memory used bytes", String(memory), String(UInt64(700_000) * 16_384))
    check("memory purgeable larger than internal", String(SystemStats.memoryUsed(internalPages: 10, purgeablePages: 20, wiredPages: 5, compressedPages: 0, pageSize: 1)), "5")

    // Network rate with 32-bit counter wrap
    check("network rate", SystemStats.rate(previous: 1_000, current: 3_000, seconds: 2).map { String($0) }, "1000.0")
    check("network rate counter wrapped", SystemStats.rate(previous: 4_294_967_000, current: 704, seconds: 1).map { String($0) }, "1000.0")
    check("network rate no time", SystemStats.rate(previous: 1, current: 2, seconds: 0).map { String($0) } ?? "nil", "nil")

    // Byte formatting
    check("bytes decimal", SystemStats.formatBytes(1_234_567, base: 1000), "1.2 MB")
    check("bytes small", SystemStats.formatBytes(512, base: 1000), "512 B")
    check("bytes binary GB", SystemStats.formatBytes(17_179_869_184, base: 1024), "16 GB")
    check("bytes binary fraction", SystemStats.formatBytes(11_811_160_064, base: 1024), "11 GB")
    check("bytes 9.5 GB", SystemStats.formatBytes(10_200_547_328, base: 1024), "9.5 GB")
    check("bytes TB", SystemStats.formatBytes(1_500_000_000_000, base: 1000), "1.5 TB")
    check("rate", SystemStats.formatRate(2_500), "2.5 KB/s")

    // ps -Aceo pid=,pcpu=,rss=,comm= -r
    let ps = """
    18302  48.5 649488 Google Chrome Helper (Aperitif Renderer)
      395  48.3  61200 WindowServer
    23899  16.2 143568 node
    bad line
    """
    let top = SystemStats.parseTopProcesses(ps, limit: 2)
    check("top count limited", String(top.count), "2")
    check("top name with spaces", top.first?.name, "Google Chrome Helper (Aperitif Renderer)")
    check("top cpu", top.first.map { String($0.cpuPercent) }, "48.5")
    check("top rss bytes", top.first.map { String($0.memoryBytes) }, String(649_488 * 1024))
    check("top second pid", top.last.map { String($0.pid) }, "395")
    check("top skips bad lines", String(SystemStats.parseTopProcesses(ps, limit: 10).count), "3")
}
