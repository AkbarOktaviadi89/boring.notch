//
//  NetworkInfo.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import Foundation

struct NetworkInfo: Equatable {
    var interface: String?
    /// "Wi-Fi", "Ethernet", "iPhone USB"…
    var interfaceName: String?
    var localIPv4: String?
    var localIPv6: String?
    var gateway: String?
    var dnsServers: [String] = []
    /// The tunnel carrying traffic when a VPN is up, such as "utun4"
    var vpnInterface: String?

    var isConnected: Bool { localIPv4 != nil || localIPv6 != nil }
}

/// What ipinfo.io says about the public address
struct PublicIPInfo: Codable, Equatable {
    let ip: String
    let city: String?
    let region: String?
    let country: String?
    /// "AS7713 PT Telekomunikasi Indonesia"
    let org: String?

    var place: String {
        [city, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The provider without the AS number
    var provider: String? {
        guard let org else { return nil }
        let parts = org.split(separator: " ", maxSplits: 1)
        return parts.count == 2 && parts[0].hasPrefix("AS") ? String(parts[1]) : org
    }
}

/// Parses scutil, route and networksetup output. Foundation only, so it can be tested without the app.
enum NetworkInfoParser {
    static let separator = "@@BORING-NOTCH-SECTION@@"
    private static let tunnelPrefixes = ["utun", "ppp", "ipsec", "tun", "tap", "wg"]

    /// The helper's report: scutil --nwi, scutil --dns, route -n get default, networksetup -listallhardwareports
    static func parse(_ report: String) -> NetworkInfo {
        let sections = report.components(separatedBy: separator)
        func section(_ index: Int) -> String { index < sections.count ? sections[index] : "" }

        var info = NetworkInfo()
        let (ipv4, ipv6) = interfaces(fromNWI: section(0))
        let all = ipv4 + ipv6
        info.vpnInterface = all.map(\.name).first { name in tunnelPrefixes.contains { name.hasPrefix($0) } }
        // The physical link: the first interface that isn't a tunnel
        let physical = { (list: [(name: String, address: String)]) in
            list.first { entry in !tunnelPrefixes.contains { entry.name.hasPrefix($0) } }
        }
        info.interface = physical(ipv4)?.name ?? physical(ipv6)?.name
        info.localIPv4 = physical(ipv4)?.address
        info.localIPv6 = physical(ipv6)?.address
        info.dnsServers = dnsServers(fromDNS: section(1))
        info.gateway = value("gateway", in: section(2))
        if let interface = info.interface {
            info.interfaceName = hardwarePorts(section(3))[interface]
        }
        return info
    }

    /// Interfaces with addresses under "IPv4 network interface information" and the IPv6 heading, in order
    static func interfaces(fromNWI text: String) -> (ipv4: [(name: String, address: String)], ipv6: [(name: String, address: String)]) {
        var ipv4: [(String, String)] = []
        var ipv6: [(String, String)] = []
        var family = 0
        var current: String?
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("IPv4 network interface") { family = 4; current = nil; continue }
            if line.hasPrefix("IPv6 network interface") { family = 6; current = nil; continue }
            if line.hasPrefix("Network interfaces") { family = 0; continue }
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            if parts[0] == "address", let current {
                if family == 4 { ipv4.append((current, parts[1])) } else if family == 6 { ipv6.append((current, parts[1])) }
            } else if parts[1].hasPrefix("flags"), !parts[0].contains(" "), parts[0] != "REACH" {
                // "en0 : flags : 0x7 (IPv4,IPv6,DNS)"
                current = parts[0]
            }
        }
        return (ipv4, ipv6)
    }

    /// The name servers of the first resolver that has no domain of its own (the default one)
    static func dnsServers(fromDNS text: String) -> [String] {
        let resolvers = text.components(separatedBy: "resolver #").dropFirst()
        for resolver in resolvers where !resolver.contains("domain   :") && !resolver.contains("domain :") {
            let servers = resolver.split(whereSeparator: \.isNewline).compactMap { line -> String? in
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).hasPrefix("nameserver[") else { return nil }
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
            if !servers.isEmpty { return servers }
        }
        return []
    }

    /// Device -> port name, from networksetup -listallhardwareports
    static func hardwarePorts(_ text: String) -> [String: String] {
        var ports: [String: String] = [:]
        var port: String?
        for line in text.split(whereSeparator: \.isNewline) {
            if let name = value("Hardware Port", in: String(line)) { port = name }
            if let device = value("Device", in: String(line)), let port { ports[device] = port }
        }
        return ports
    }

    /// "  gateway: 192.168.1.1" -> "192.168.1.1"
    private static func value(_ key: String, in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == key {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// Megabits per second
    static func mbps(bytes: Int, seconds: Double) -> Double {
        guard seconds > 0 else { return 0 }
        return Double(bytes) * 8 / seconds / 1_000_000
    }

    /// "245 Mbps", "8.4 Mbps", "0.62 Mbps"
    static func formatSpeed(_ mbps: Double) -> String {
        switch mbps {
        case 100...: return String(format: "%.0f Mbps", mbps)
        case 1...: return String(format: "%.1f Mbps", mbps)
        default: return String(format: "%.2f Mbps", mbps)
        }
    }
}
