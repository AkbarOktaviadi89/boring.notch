//
//  AppUsageTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-28.
//

import Foundation

func runAppUsageTests() {
    let ps = """
      395     1    88  39.5 130080 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
    89612     1   501   1.5 200000 /Applications/Claude.app/Contents/MacOS/Claude
    89615 89612   501  17.9  90144 /Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper
    89761 89612   501   8.0 701184 /Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer)
     3213     1   501   7.0 236368 /Applications/Boring Notch.app/Contents/MacOS/Boring Notch
    10750     1   501   0.7  12000 /opt/homebrew/opt/redis/bin/redis-server
      500     1   501   0.1   9000 /System/Library/CoreServices/Finder.app/Contents/MacOS/Finder
      garbage line
    """
    let top = """
    Processes: 600 total
    PID    POWER
    395    0.0
    89615  0.0
    Processes: 600 total, 4 running
    Load Avg: 2.1
    PID    POWER
    395    50.1
    89615  22.3
    89761  9.1
    89612  0.4
    10750  0.9
    """

    let processes = AppUsageStats.parseProcesses(ps)
    check("ps parses rows", String(processes.count), "7")
    check("ps keeps spaces in path", processes[3].path, "/Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer)")
    check("ps memory in bytes", String(processes[1].memoryBytes), "204800000")

    let energy = AppUsageStats.parseEnergy(top)
    check("top uses last sample", String(energy[395] ?? -1), "50.1")
    check("top all pids", String(energy.count), "5")
    check("top empty", String(AppUsageStats.parseEnergy("nothing").count), "0")

    check("bundle of helper", AppUsageStats.bundlePath(of: "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper") ?? "nil", "/Applications/Claude.app")
    check("bundle of tool", AppUsageStats.bundlePath(of: "/opt/homebrew/bin/node") ?? "nil", "nil")

    let rows = AppUsageStats.group(processes, energy: energy, currentUID: 501)
    let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
    let claude = byID["/Applications/Claude.app"]
    check("app groups helpers", String(claude?.processCount ?? 0), "3")
    check("app name", claude?.name ?? "", "Claude")
    check("app cpu summed", String(format: "%.1f", claude?.cpuPercent ?? 0), "27.4")
    check("app energy summed", String(format: "%.1f", claude?.energy ?? 0), "31.8")
    check("app quits main process", String(claude?.quitPID ?? -1), "89612")
    check("loose process row", byID["pid:10750"]?.name ?? "", "redis-server")
    check("loose process quittable", String(byID["pid:10750"]?.quitPID ?? -1), "10750")
    check("system process not quittable", String(byID["pid:395"]?.quitPID ?? -1), "-1")
    check("finder not quittable", String(byID["/System/Library/CoreServices/Finder.app"]?.quitPID ?? -1), "-1")
    check("notch not quittable", String(byID["/Applications/Boring Notch.app"]?.quitPID ?? -1), "-1")

    check("sort cpu", AppUsageStats.sorted(rows, by: .cpu).prefix(2).map(\.name).joined(separator: ","), "WindowServer,Claude")
    check("sort memory", AppUsageStats.sorted(rows, by: .memory).first?.name ?? "", "Claude")
    check("sort energy", AppUsageStats.sorted(rows, by: .energy).prefix(2).map(\.name).joined(separator: ","), "WindowServer,Claude")

    // Guard
    check("guard user app", String(ProcessGuard.canForceQuit(path: "/Applications/Slack.app/Contents/MacOS/Slack", uid: 501, currentUID: 501)), "true")
    check("guard other user", String(ProcessGuard.canForceQuit(path: "/Applications/Slack.app/Contents/MacOS/Slack", uid: 0, currentUID: 501)), "false")
    check("guard loginwindow", String(ProcessGuard.canForceQuit(path: "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow", uid: 501, currentUID: 501)), "false")
    check("guard usr bin", String(ProcessGuard.canForceQuit(path: "/usr/bin/python3", uid: 501, currentUID: 501)), "false")
    check("guard usr local ok", String(ProcessGuard.canForceQuit(path: "/usr/local/bin/node", uid: 501, currentUID: 501)), "true")
    check("guard apple app ok", String(ProcessGuard.canForceQuit(path: "/System/Applications/Mail.app/Contents/MacOS/Mail", uid: 501, currentUID: 501)), "true")
    check("guard relative path", String(ProcessGuard.canForceQuit(path: "node", uid: 501, currentUID: 501)), "false")
}
