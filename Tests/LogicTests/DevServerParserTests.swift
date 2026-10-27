//
//  DevServerParserTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Foundation

func runDevServerTests() {
    let listen = """
    p630
    cControlCenter
    f9
    n*:7000
    f10
    n*:7000
    f11
    n*:5000
    p726
    credis-server
    f6
    n127.0.0.1:6379
    f7
    n[::1]:6379
    p10750
    cnode
    f22
    n127.0.0.1:5173
    f23
    n[::1]:5173
    p20001
    cCode Helper (Plugin)
    f40
    n192.168.1.5:3000

    """
    let processes = DevServerParser.parseListening(listen)
    check("listen process count", String(processes.count), "4")
    check("listen pids", processes.map { String($0.pid) }.joined(separator: ","), "630,726,10750,20001")
    check("ports merged and deduplicated", processes.first?.ports.map(String.init).joined(separator: ","), "5000,7000")
    check("command with spaces", processes.last?.command, "Code Helper (Plugin)")
    check("wildcard is exposed", processes.first.map { String($0.isExposed) }, "true")
    check("loopback v4+v6 is local", processes[1].isExposed ? "exposed" : "local", "local")
    check("lan address is exposed", processes[3].isExposed ? "exposed" : "local", "exposed")
    check("empty output", String(DevServerParser.parseListening("").count), "0")

    let details = DevServerParser.parseDetails("""
    630	/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter	/
    10750	/opt/homebrew/Cellar/node/22.1.0/bin/node	/Users/akbarokta/Data/Piko/ijeon/jeonme/apps/api
    726		
    garbage line
    """)
    check("details path", details[630]?.executablePath, "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter")
    check("details cwd", details[10750]?.workingDirectory, "/Users/akbarokta/Data/Piko/ijeon/jeonme/apps/api")
    check("details empty fields are nil", details[726]?.executablePath == nil && details[726]?.workingDirectory == nil ? "nil" : "set", "nil")
    check("details skips garbage", String(details.count), "3")

    let merged = DevServerParser.merge(processes, details: details)
    check("system detected", merged.first { $0.pid == 630 }.map { String($0.isSystem) }, "true")
    check("dev server not system", merged.first { $0.pid == 10750 }.map { String($0.isSystem) }, "false")
    check("project name from cwd", merged.first { $0.pid == 10750 }?.projectName, "api")
    check("no project name for root cwd", merged.first { $0.pid == 630 }?.projectName ?? "nil", "nil")
    check("sorted: non-system first, then lowest port", merged.map { String($0.pid) }.joined(separator: ","), "20001,10750,726,630")
}
