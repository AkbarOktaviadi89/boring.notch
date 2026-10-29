//
//  NetworkInfoTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import Foundation

func runNetworkInfoTests() {
    let nwi = """
    Network information

    IPv4 network interface information
         en0 : flags      : 0x7 (IPv4,IPv6,DNS)
               address    : 192.168.1.7
               reach      : 0x00000002 (Reachable)

       REACH : flags 0x00000002 (Reachable)

    IPv6 network interface information
         en0 : flags      : 0x7 (IPv4,IPv6,DNS)
               address    : 2404:c0:dc01:4674:10c2:debe:5c28:9104
               reach      : 0x00000002 (Reachable)

       REACH : flags 0x00000002 (Reachable)

    Network interfaces: en0
    """
    let vpnNWI = """
    IPv4 network interface information
       utun4 : flags      : 0x5 (IPv4,DNS)
               address    : 10.8.0.2
         en0 : flags      : 0x7 (IPv4,IPv6,DNS)
               address    : 192.168.1.7
    Network interfaces: utun4 en0
    """
    let dns = """
    DNS configuration

    resolver #1
      nameserver[0] : 2404:c0:9302::1:9
      nameserver[1] : 192.168.1.1
      if_index : 14 (en0)

    resolver #2
      domain   : local
      options  : mdns
    """
    let scopedFirst = """
    resolver #1
      domain   : corp.example
      nameserver[0] : 10.0.0.53

    resolver #2
      nameserver[0] : 1.1.1.1
    """
    let route = """
       route to: default
    destination: default
        gateway: 192.168.1.1
      interface: en0
    """
    let ports = """
    Hardware Port: Wi-Fi
    Device: en0
    Ethernet Address: aa:bb

    Hardware Port: Thunderbolt Bridge
    Device: bridge0
    """
    let sep = "\n" + NetworkInfoParser.separator + "\n"

    let info = NetworkInfoParser.parse(nwi + sep + dns + sep + route + sep + ports)
    check("net interface", info.interface ?? "nil", "en0")
    check("net interface name", info.interfaceName ?? "nil", "Wi-Fi")
    check("net ipv4", info.localIPv4 ?? "nil", "192.168.1.7")
    check("net ipv6", info.localIPv6 ?? "nil", "2404:c0:dc01:4674:10c2:debe:5c28:9104")
    check("net gateway", info.gateway ?? "nil", "192.168.1.1")
    check("net dns", info.dnsServers.joined(separator: ","), "2404:c0:9302::1:9,192.168.1.1")
    check("net no vpn", info.vpnInterface ?? "nil", "nil")
    check("net connected", String(info.isConnected), "true")

    let vpn = NetworkInfoParser.parse(vpnNWI + sep + dns + sep + route + sep + ports)
    check("net vpn found", vpn.vpnInterface ?? "nil", "utun4")
    check("net vpn keeps physical ip", vpn.localIPv4 ?? "nil", "192.168.1.7")
    check("net vpn physical interface", vpn.interface ?? "nil", "en0")

    check("dns skips scoped resolver", NetworkInfoParser.dnsServers(fromDNS: scopedFirst).joined(separator: ","), "1.1.1.1")
    check("net offline", String(NetworkInfoParser.parse("Network information\n\nNo network connection").isConnected), "false")

    // Public IP
    let json = #"{"ip":"36.71.1.2","city":"Bandung","region":"West Java","country":"ID","org":"AS7713 PT Telekomunikasi Indonesia"}"#
    let ipInfo = try? JSONDecoder().decode(PublicIPInfo.self, from: Data(json.utf8))
    check("public ip", ipInfo?.ip ?? "nil", "36.71.1.2")
    check("public place", ipInfo?.place ?? "nil", "Bandung, ID")
    check("public provider", ipInfo?.provider ?? "nil", "PT Telekomunikasi Indonesia")
    let bare = try? JSONDecoder().decode(PublicIPInfo.self, from: Data(#"{"ip":"1.2.3.4"}"#.utf8))
    check("public minimal", (bare?.place ?? "nil") + "|" + (bare?.provider ?? "nil"), "|nil")

    // Speed
    check("mbps", String(format: "%.1f", NetworkInfoParser.mbps(bytes: 25_000_000, seconds: 2)), "100.0")
    check("mbps zero time", String(NetworkInfoParser.mbps(bytes: 10, seconds: 0)), "0.0")
    check("speed big", NetworkInfoParser.formatSpeed(245.4), "245 Mbps")
    check("speed mid", NetworkInfoParser.formatSpeed(8.42), "8.4 Mbps")
    check("speed small", NetworkInfoParser.formatSpeed(0.625), "0.62 Mbps")
}
