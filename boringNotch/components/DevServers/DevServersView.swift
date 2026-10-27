//
//  DevServersView.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Defaults
import SwiftUI

struct DevServersView: View {
    @ObservedObject var monitor = DevServerMonitor.shared
    @Default(.devServersShowSystem) var showSystem

    private var visible: [ListeningProcess] {
        showSystem ? monitor.processes : monitor.processes.filter { !$0.isSystem }
    }

    private var systemCount: Int {
        monitor.processes.filter(\.isSystem).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            content
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { monitor.startMonitoring() }
        .onDisappear { monitor.stopMonitoring() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            MonitorSectionPicker()
            Text("\(visible.count) listening")
                .font(.caption)
                .foregroundStyle(.gray)
            Spacer()
            if systemCount > 0 {
                Toggle("Show system (\(systemCount))", isOn: $showSystem)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
            Button {
                Task { await monitor.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color(nsColor: .secondarySystemFill)))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Refresh")
        }
    }

    @ViewBuilder
    private var content: some View {
        if !monitor.hasLoaded {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if monitor.helperUnavailable {
            placeholder("Couldn't reach the Boring Notch helper", icon: "exclamationmark.triangle")
        } else if visible.isEmpty {
            placeholder("No servers listening", icon: "moon.zzz")
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(visible) { process in
                        DevServerRow(process: process, isStopping: monitor.stopping.contains(process.pid))
                    }
                }
            }
            .allowsScrollingInOpenNotch()
        }
    }

    private func placeholder(_ text: LocalizedStringKey, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
            Text(text)
                .font(.callout)
        }
        .foregroundStyle(.gray)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DevServerRow: View {
    let process: ListeningProcess
    let isStopping: Bool
    @State private var isHovering = false

    private let maxPorts = 4

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: process.isExposed ? "network" : "circle.fill")
                .font(.system(size: process.isExposed ? 11 : 7))
                .foregroundStyle(process.isExposed ? .orange : .green)
                .frame(width: 14)
                .help(process.isExposed
                      ? "Listening on all interfaces: other devices on your network can reach it"
                      : "Only reachable from this Mac")

            VStack(alignment: .leading, spacing: 0) {
                Text(process.command)
                    .font(.system(.callout, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(process.projectName ?? "pid \(process.pid)")
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: 150, alignment: .leading)
            .help(process.workingDirectory ?? process.executablePath ?? "")

            HStack(spacing: 4) {
                ForEach(process.ports.prefix(maxPorts), id: \.self) { port in
                    Button {
                        DevServerMonitor.shared.open(port: port)
                    } label: {
                        Text(":\(String(port))")
                            .font(.system(.caption, design: .monospaced, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.effectiveAccent.opacity(0.3)))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Open http://localhost:\(String(port))")
                    .contextMenu {
                        Button("Open in browser") { DevServerMonitor.shared.open(port: port) }
                        Button("Copy URL") { DevServerMonitor.shared.copyURL(port: port) }
                    }
                }
                if process.ports.count > maxPorts {
                    Text("+\(process.ports.count - maxPorts)")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }

            Spacer(minLength: 4)

            if !process.isSystem {
                Button {
                    Task { await DevServerMonitor.shared.stop(process) }
                } label: {
                    Label(isStopping ? "Force quit" : "Stop", systemImage: isStopping ? "xmark.octagon.fill" : "stop.fill")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(isStopping ? Color.red.opacity(0.6) : Color(nsColor: .secondarySystemFill)))
                }
                .buttonStyle(PlainButtonStyle())
                .opacity(isHovering || isStopping ? 1 : 0)
                .help(isStopping ? "Still running: send SIGKILL" : "Stop (SIGTERM)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.white.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

#Preview {
    DevServersView()
        .frame(width: 600, height: 150)
        .background(.black)
}
