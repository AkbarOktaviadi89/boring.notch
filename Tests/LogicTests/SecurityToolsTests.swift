//
//  SecurityToolsTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Foundation

func runSecurityToolsTests() {
    // Regex
    let emails = try? SecurityTransforms.regexMatches(pattern: #"(\w+)@(\w+)\.com"#, in: "a@b.com, cc@dd.com and x@y.org")
    check("regex matches", emails?.primary, "a@b.com\ncc@dd.com")
    check("regex groups", emails?.detail, "2 matches · groups: [a, b] [cc, dd]")
    check("regex no groups", (try? SecurityTransforms.regexMatches(pattern: #"\d+"#, in: "id=12&page=3"))?.detail, "2 matches")
    check("regex inline flag", (try? SecurityTransforms.regexMatches(pattern: "(?i)admin", in: "Admin ADMIN"))?.primary, "Admin\nADMIN")
    checkThrows("regex invalid") { try SecurityTransforms.regexMatches(pattern: "(", in: "x") }
    checkThrows("regex empty pattern") { try SecurityTransforms.regexMatches(pattern: "", in: "x") }
    checkThrows("regex no match") { try SecurityTransforms.regexMatches(pattern: "z", in: "abc") }

    // Diff
    let changed = SecurityTransforms.lineDiff("a\nb\nc", "a\nx\nc")
    check("diff replace", changed.primary, "  a\n- b\n+ x\n  c")
    check("diff replace summary", changed.detail, "1 added, 1 removed")
    let appended = SecurityTransforms.lineDiff("1\n2\n", "1\r\n2\r\n3")
    check("diff append, CRLF and trailing newline", appended.primary, "  1\n  2\n+ 3")
    check("diff append summary", appended.detail, "1 added, 0 removed")
    check("diff identical", SecurityTransforms.lineDiff("same\ntext", "same\ntext").detail, "No differences")

    // CIDR
    let lan = try? SecurityTransforms.cidr("192.168.1.10/24")
    check("cidr network", lan?.primary, "192.168.1.0/24")
    contains("cidr netmask", lan?.detail, "Netmask: 255.255.255.0 (wildcard 0.0.0.255)")
    contains("cidr hosts", lan?.detail, "Hosts: 192.168.1.1 – 192.168.1.254 (254 usable)")
    contains("cidr broadcast", lan?.detail, "Broadcast: 192.168.1.255")
    contains("cidr private", lan?.detail, "Type: Private (RFC 1918)")
    contains("cidr /8 host count", (try? SecurityTransforms.cidr("10.0.0.0/8"))?.detail, "(16777214 usable)")
    let single = try? SecurityTransforms.cidr("8.8.8.8")
    check("cidr plain ip is /32", single?.primary, "8.8.8.8/32")
    contains("cidr /32 hosts", single?.detail, "Hosts: 8.8.8.8 (1 address)")
    contains("cidr public", single?.detail, "Type: Public")
    check("cidr /32 has no broadcast", (single?.detail?.contains("Broadcast") ?? true) ? "has" : "none", "none")
    contains("cidr /31", (try? SecurityTransforms.cidr("10.0.0.0/31"))?.detail, "Hosts: 10.0.0.0 – 10.0.0.1 (2 usable, point-to-point)")
    contains("cidr metadata", (try? SecurityTransforms.cidr("169.254.169.254"))?.detail, "Type: Link-local (cloud metadata range)")
    contains("cidr loopback", (try? SecurityTransforms.cidr("127.0.0.1/8"))?.detail, "Type: Loopback")
    contains("cidr cgnat", (try? SecurityTransforms.cidr("100.64.0.1"))?.detail, "Type: Carrier-grade NAT (RFC 6598)")
    contains("cidr 172.16/12 private", (try? SecurityTransforms.cidr("172.31.255.1"))?.detail, "Type: Private (RFC 1918)")
    contains("cidr 172.32 public", (try? SecurityTransforms.cidr("172.32.0.1"))?.detail, "Type: Public")
    check("cidr /0", (try? SecurityTransforms.cidr("1.2.3.4/0"))?.primary, "0.0.0.0/0")
    checkThrows("cidr bad octet") { try SecurityTransforms.cidr("300.1.1.1/24") }
    checkThrows("cidr bad prefix") { try SecurityTransforms.cidr("1.2.3.4/33") }
    checkThrows("cidr garbage") { try SecurityTransforms.cidr("not an ip") }
}
