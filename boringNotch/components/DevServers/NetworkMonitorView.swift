//
//  NetworkMonitorView.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import SwiftUI

/// Monitor › Network: the connection, the public address and a speed test
struct NetworkMonitorView: View {
    @ObservedObject var network = NetworkMonitor.shared
    @State private var copiedIP = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                MonitorSectionPicker()
                Spacer()
                vpnBadge
            }

            if network.helperUnavailable {
                Text("The helper that reads the network settings isn't running. Reopen Boring Notch to restart it.")
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    localCard
                    publicCard
                    speedCard
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { network.startMonitoring() }
        .onDisappear { network.stopMonitoring() }
    }

    // MARK: - VPN

    @ViewBuilder
    private var vpnBadge: some View {
        if let tunnel = network.info.vpnInterface {
            Label("VPN on · \(tunnel)", systemImage: "lock.shield.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.green)
                .help("Traffic goes through the \(tunnel) tunnel")
        } else if network.hasLoaded {
            Label("No VPN", systemImage: "lock.open")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.gray)
        }
    }

    // MARK: - Local

    private var localCard: some View {
        card(title: "This Mac", icon: network.info.interfaceName == "Wi-Fi" ? "wifi" : "network") {
            if !network.hasLoaded {
                Text("Reading…").font(.caption).foregroundStyle(.gray)
            } else if !network.info.isConnected {
                Text("Not connected").font(.callout.weight(.semibold)).foregroundStyle(.orange)
            } else {
                row("Link", [network.info.interfaceName, network.info.interface.map { "(\($0))" }].compactMap { $0 }.joined(separator: " "))
                row("IP", network.info.localIPv4 ?? network.info.localIPv6 ?? "–")
                row("Gateway", network.info.gateway ?? "–")
                row("DNS", network.info.dnsServers.prefix(2).joined(separator: ", "), help: network.info.dnsServers.joined(separator: "\n"))
            }
        }
        .frame(width: 210)
    }

    // MARK: - Public

    private var publicCard: some View {
        card(title: "Public address", icon: "globe") {
            if let info = network.publicIP {
                HStack(spacing: 4) {
                    Text(info.ip)
                        .font(.system(.callout, design: .monospaced, weight: .semibold))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(info.ip, forType: .string)
                        ClipboardWatcher.shared.ignoreCurrentChange()
                        withAnimation(.smooth) { copiedIP = true }
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            withAnimation(.smooth) { copiedIP = false }
                        }
                    } label: {
                        Image(systemName: copiedIP ? "checkmark" : "doc.on.doc").font(.system(size: 10))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundStyle(.gray)
                    .help("Copy the address")
                }
                if !info.place.isEmpty {
                    Text(info.place).font(.caption).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                }
                if let provider = info.provider {
                    Text(provider).font(.caption2).foregroundStyle(.gray).lineLimit(1).help(info.org ?? provider)
                }
            } else if network.isLoadingPublicIP {
                ProgressView().controlSize(.small)
            } else {
                Text(network.publicIPError ?? "–").font(.caption).foregroundStyle(.gray)
            }
        } accessory: {
            Button { Task { await network.refreshPublicIP() } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundStyle(.gray)
            .disabled(network.isLoadingPublicIP)
            .help("Look it up again (asks ipinfo.io)")
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Speed

    private var speedCard: some View {
        card(title: "Speed", icon: "speedometer") {
            HStack(spacing: 10) {
                metric("Ping", network.pingMilliseconds.map { String(format: "%.0f ms", $0) }, active: network.speedPhase == .ping)
                metric("Down", network.downloadMbps.map(NetworkInfoParser.formatSpeed), active: network.speedPhase == .download)
                metric("Up", network.uploadMbps.map(NetworkInfoParser.formatSpeed), active: network.speedPhase == .upload)
            }
            if let error = network.speedError {
                Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(2)
            }
        } accessory: {
            Button {
                isTesting ? network.cancelSpeedTest() : network.runSpeedTest()
            } label: {
                Text(isTesting ? "Stop" : (network.speedPhase == .done ? "Again" : "Run"))
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(isTesting ? Color(nsColor: .secondarySystemFill) : Color.effectiveAccent))
                    .foregroundStyle(.white)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Measures against Cloudflare's speed test servers and uses about 35 MB of data")
        }
        .frame(width: 200)
    }

    private var isTesting: Bool {
        [.ping, .download, .upload].contains(network.speedPhase)
    }

    private func metric(_ title: String, _ value: String?, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.gray)
            if active {
                ProgressView().controlSize(.mini)
            } else {
                Text(value ?? "–")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    // MARK: - Building blocks

    private func row(_ label: String, _ value: String, help: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.gray)
                .frame(width: 46, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(help ?? value)
        }
    }

    private func card<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        card(title: title, icon: icon, content: content) { EmptyView() }
    }

    private func card<Content: View, Accessory: View>(title: String, icon: String, @ViewBuilder content: () -> Content,
                                                       @ViewBuilder accessory: () -> Accessory) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Label(title, systemImage: icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.gray)
                Spacer(minLength: 0)
                accessory()
            }
            content()
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }
}
