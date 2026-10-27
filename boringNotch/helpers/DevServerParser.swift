//
//  DevServerParser.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Foundation

struct ListeningProcess: Identifiable, Equatable {
    let pid: Int32
    let command: String
    /// Sorted, without duplicates (IPv4 and IPv6 sockets usually share a port)
    var ports: [Int]
    /// Listens on all interfaces or a non-loopback address, so other machines on the network can reach it
    var isExposed: Bool
    var executablePath: String?
    var workingDirectory: String?

    var id: Int32 { pid }

    var isSystem: Bool {
        guard let executablePath else { return false }
        return ["/System/", "/usr/libexec/", "/usr/sbin/", "/Library/Apple/"].contains { executablePath.hasPrefix($0) }
    }

    /// Folder the process was started from, usually the project
    var projectName: String? {
        guard let workingDirectory, workingDirectory != "/" else { return nil }
        return URL(fileURLWithPath: workingDirectory).lastPathComponent
    }
}

struct ProcessDetails: Equatable {
    var executablePath: String?
    var workingDirectory: String?
}

/// Parses what the XPC helper reports about listening TCP sockets. Foundation only, so it can be tested without the app.
enum DevServerParser {
    /// Parses `lsof +c 0 -nP -iTCP -sTCP:LISTEN -F pcn`: one field per line, keyed by its first character
    static func parseListening(_ output: String) -> [ListeningProcess] {
        var processes: [ListeningProcess] = []
        var current: ListeningProcess?

        for line in output.split(whereSeparator: \.isNewline) {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())
            switch field {
            case "p":
                if let current { processes.append(current) }
                current = Int32(value).map { ListeningProcess(pid: $0, command: "", ports: [], isExposed: false) }
            case "c":
                if let process = current {
                    current = ListeningProcess(pid: process.pid, command: value, ports: process.ports, isExposed: process.isExposed)
                }
            case "n":
                guard let (port, isLoopback) = parseAddress(value) else { continue }
                if !(current?.ports.contains(port) ?? true) {
                    current?.ports.append(port)
                    current?.ports.sort()
                }
                if !isLoopback { current?.isExposed = true }
            default:
                continue
            }
        }
        if let current { processes.append(current) }
        return processes.filter { !$0.ports.isEmpty }
    }

    /// "*:3000", "127.0.0.1:5173", "[::1]:8080", "192.168.1.5:3000"
    static func parseAddress(_ address: String) -> (port: Int, isLoopback: Bool)? {
        guard let colon = address.lastIndex(of: ":"), let port = Int(address[address.index(after: colon)...]) else {
            return nil
        }
        let host = address[..<colon]
        let isLoopback = host.hasPrefix("127.") || host == "[::1]" || host == "localhost"
        return (port, isLoopback)
    }

    /// Parses "pid<TAB>executable path<TAB>working directory" lines; empty fields mean unknown
    static func parseDetails(_ output: String) -> [Int32: ProcessDetails] {
        var details: [Int32: ProcessDetails] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3, let pid = Int32(fields[0]) else { continue }
            details[pid] = ProcessDetails(
                executablePath: fields[1].isEmpty ? nil : String(fields[1]),
                workingDirectory: fields[2].isEmpty ? nil : String(fields[2])
            )
        }
        return details
    }

    /// Adds paths and sorts: the user's own servers first, then by lowest port
    static func merge(_ processes: [ListeningProcess], details: [Int32: ProcessDetails]) -> [ListeningProcess] {
        processes
            .map { process in
                var process = process
                process.executablePath = details[process.pid]?.executablePath
                process.workingDirectory = details[process.pid]?.workingDirectory
                return process
            }
            .sorted { lhs, rhs in
                if lhs.isSystem != rhs.isSystem { return !lhs.isSystem }
                return (lhs.ports.first ?? .max) < (rhs.ports.first ?? .max)
            }
    }
}
