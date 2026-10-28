//
//  AppUsage.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-28.
//

import Foundation

struct ProcessSample: Equatable {
    let pid: Int32
    let uid: UInt32
    let cpuPercent: Double
    let memoryBytes: UInt64
    let path: String
}

/// One row of the Apps monitor: an app with all its helper processes, or a single process outside any app
struct AppUsage: Identifiable, Equatable {
    /// The app's bundle path, or "pid:<n>" for a lone process
    let id: String
    let name: String
    let bundlePath: String?
    let cpuPercent: Double
    let memoryBytes: UInt64
    /// Activity Monitor's Energy Impact; higher drains the battery faster
    let energy: Double
    let processCount: Int
    /// The process to force quit, nil when this row can't be quit from the notch
    let quitPID: Int32?
}

enum AppUsageSort: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "Memory"
    case energy = "Energy"

    var id: Self { self }
}

/// Parses ps and top output into per-app usage. Foundation only, so it can be tested without the app.
enum AppUsageStats {
    /// Lines of `ps -Axo pid=,ppid=,uid=,pcpu=,rss=,comm=`; comm is the full executable path and may contain spaces
    static func parseProcesses(_ output: String) -> [ProcessSample] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
            guard fields.count == 6,
                  let pid = Int32(fields[0]),
                  let uid = UInt32(fields[2]),
                  let cpu = Double(fields[3]),
                  let rss = UInt64(fields[4])
            else { return nil }
            return ProcessSample(pid: pid, uid: uid, cpuPercent: cpu, memoryBytes: rss * 1024, path: String(fields[5]))
        }
    }

    /// pid -> POWER from `top -l 2 -stats pid,power`. Only the last sample counts: the first one is always zero.
    static func parseEnergy(_ output: String) -> [Int32: Double] {
        let lines = output.split(whereSeparator: \.isNewline)
        guard let header = lines.lastIndex(where: { $0.split(separator: " ").first == "PID" }) else { return [:] }
        var energy: [Int32: Double] = [:]
        for line in lines[(header + 1)...] {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 2, let pid = Int32(fields[0]), let power = Double(fields[1]) else { continue }
            energy[pid] = power
        }
        return energy
    }

    /// "/Applications/Google Chrome.app" for any process inside it, helpers in nested apps included
    static func bundlePath(of path: String) -> String? {
        if let range = path.range(of: ".app/") {
            return String(path[..<range.lowerBound]) + ".app"
        }
        return path.hasSuffix(".app") ? path : nil
    }

    static func group(_ processes: [ProcessSample], energy: [Int32: Double], currentUID: UInt32) -> [AppUsage] {
        var apps: [String: [ProcessSample]] = [:]
        var loose: [ProcessSample] = []
        for process in processes {
            if let bundle = bundlePath(of: process.path) {
                apps[bundle, default: []].append(process)
            } else {
                loose.append(process)
            }
        }

        var rows: [AppUsage] = apps.map { bundle, members in
            // The app's own executable, not one of its helpers
            let main = members
                .filter { $0.path.hasPrefix(bundle + "/Contents/MacOS/") }
                .min { $0.pid < $1.pid }
            let quitPID = main.flatMap { process in
                ProcessGuard.canForceQuit(path: process.path, uid: process.uid, currentUID: currentUID) ? process.pid : nil
            }
            return AppUsage(
                id: bundle,
                name: ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension,
                bundlePath: bundle,
                cpuPercent: members.reduce(0) { $0 + $1.cpuPercent },
                memoryBytes: members.reduce(0) { $0 + $1.memoryBytes },
                energy: members.reduce(0) { $0 + (energy[$1.pid] ?? 0) },
                processCount: members.count,
                quitPID: quitPID
            )
        }
        rows += loose.map { process in
            AppUsage(
                id: "pid:\(process.pid)",
                name: (process.path as NSString).lastPathComponent,
                bundlePath: nil,
                cpuPercent: process.cpuPercent,
                memoryBytes: process.memoryBytes,
                energy: energy[process.pid] ?? 0,
                processCount: 1,
                quitPID: ProcessGuard.canForceQuit(path: process.path, uid: process.uid, currentUID: currentUID) ? process.pid : nil
            )
        }
        return rows
    }

    /// Biggest first; ties keep a stable order by name
    static func sorted(_ apps: [AppUsage], by sort: AppUsageSort) -> [AppUsage] {
        func value(_ app: AppUsage) -> Double {
            switch sort {
            case .cpu: return app.cpuPercent
            case .memory: return Double(app.memoryBytes)
            case .energy: return app.energy
            }
        }
        return apps.sorted { value($0) != value($1) ? value($0) > value($1) : $0.name < $1.name }
    }
}
