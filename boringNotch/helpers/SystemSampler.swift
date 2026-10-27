//
//  SystemSampler.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Darwin
import Foundation

/// Reads raw system counters. All of these are allowed inside the app sandbox.
enum SystemSampler {
    static func cpuTicks() -> [CPUTicks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info
        else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        return (0..<Int(cpuCount)).map { cpu in
            let base = Int(CPU_STATE_MAX) * cpu
            return CPUTicks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            )
        }
    }

    static func memory() -> (used: UInt64, total: UInt64)? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let used = SystemStats.memoryUsed(
            internalPages: UInt64(stats.internal_page_count),
            purgeablePages: UInt64(stats.purgeable_count),
            wiredPages: UInt64(stats.wire_count),
            compressedPages: UInt64(stats.compressor_page_count),
            pageSize: UInt64(vm_kernel_page_size)
        )
        return (used, ProcessInfo.processInfo.physicalMemory)
    }

    /// Received and sent byte counters per physical interface (Wi-Fi, Ethernet, USB) that is up.
    /// VPN tunnels, bridges and AWDL are skipped: their traffic also passes through an en* interface.
    static func networkCounters() -> [String: (received: UInt64, sent: UInt64)] {
        var counters: [String: (received: UInt64, sent: UInt64)] = [:]
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return counters }
        defer { freeifaddrs(first) }

        var cursor = first
        while let entry = cursor?.pointee {
            defer { cursor = entry.ifa_next }
            let name = String(cString: entry.ifa_name)
            guard name.hasPrefix("en"),
                  let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  entry.ifa_flags & UInt32(IFF_UP) != 0,
                  let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self).pointee
            else { continue }
            counters[name] = (UInt64(data.ifi_ibytes), UInt64(data.ifi_obytes))
        }
        return counters
    }

    static func disk() -> (free: UInt64, total: UInt64)? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity
        else { return nil }
        return (UInt64(max(0, free)), UInt64(max(0, total)))
    }
}
