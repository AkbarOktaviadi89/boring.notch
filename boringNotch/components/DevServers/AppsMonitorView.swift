//
//  AppsMonitorView.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-28.
//

import Defaults
import SwiftUI

/// Monitor › Apps: which apps use the most CPU, memory or energy, with Force Quit
struct AppsMonitorView: View {
    @ObservedObject var monitor = AppUsageMonitor.shared
    @Default(.monitorAppSort) var sort

    private let cpuWidth: CGFloat = 46
    private let memoryWidth: CGFloat = 58
    private let energyWidth: CGFloat = 46
    private let actionWidth: CGFloat = 78

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                MonitorSectionPicker()
                Spacer()
                Text("Sort")
                    .font(.caption)
                    .foregroundStyle(.gray)
                CapsuleSegmentedPicker(options: AppUsageSort.allCases, selection: $sort, title: \.rawValue)
            }

            columnHeader

            if monitor.helperUnavailable {
                message("The helper that reads other apps isn't running. Reopen Boring Notch to restart it.")
            } else if !monitor.hasLoaded {
                message("Measuring…")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 1) {
                        ForEach(monitor.apps) { app in
                            AppUsageRow(app: app, sort: sort, widths: (cpuWidth, memoryWidth, energyWidth, actionWidth))
                        }
                    }
                }
                .allowsScrollingInOpenNotch()
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { monitor.startMonitoring() }
        .onDisappear { monitor.stopMonitoring() }
        .onChange(of: sort) { monitor.resort() }
    }

    private var columnHeader: some View {
        HStack(spacing: 6) {
            Text("App")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 22)
            headerLabel("CPU", .cpu, width: cpuWidth)
            headerLabel("Memory", .memory, width: memoryWidth)
            headerLabel("Energy", .energy, width: energyWidth)
                .help("Energy Impact, as in Activity Monitor: the higher, the faster it drains the battery")
            Color.clear.frame(width: actionWidth, height: 1)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.gray)
        .padding(.horizontal, 6)
    }

    private func headerLabel(_ title: LocalizedStringKey, _ column: AppUsageSort, width: CGFloat) -> some View {
        Text(title)
            .foregroundStyle(sort == column ? Color.effectiveAccent : .gray)
            .frame(width: width, alignment: .trailing)
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.gray)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AppUsageRow: View {
    let app: AppUsage
    let sort: AppUsageSort
    let widths: (cpu: CGFloat, memory: CGFloat, energy: CGFloat, action: CGFloat)
    @ObservedObject var monitor = AppUsageMonitor.shared
    @State private var isHovering = false
    /// First click arms the button, the second one force quits
    @State private var confirming = false
    @State private var isQuitting = false
    @State private var failed = false

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if let icon = monitor.icon(for: app) {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "gearshape").resizable().foregroundStyle(.gray)
                }
            }
            .frame(width: 16, height: 16)

            HStack(spacing: 4) {
                Text(app.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if app.processCount > 1 {
                    Text("\(app.processCount)")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                        .help("\(app.processCount) processes")
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)

            value(String(format: "%.1f%%", app.cpuPercent), column: .cpu, width: widths.cpu,
                  warn: app.cpuPercent > 80)
            value(SystemStats.formatBytes(app.memoryBytes, base: 1024), column: .memory, width: widths.memory,
                  warn: app.memoryBytes > 4 << 30)
            value(String(format: "%.1f", app.energy), column: .energy, width: widths.energy,
                  warn: app.energy > 50)

            quitButton
                .frame(width: widths.action, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.white.opacity(0.06) : .clear)
        )
        .onHover { hovering in
            isHovering = hovering
            if !hovering { confirming = false }
        }
        .help(app.bundlePath ?? app.name)
    }

    private func value(_ text: String, column: AppUsageSort, width: CGFloat, warn: Bool) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced, weight: sort == column ? .semibold : .regular))
            .foregroundStyle(warn ? .orange : (sort == column ? .white : .gray))
            .lineLimit(1)
            .frame(width: width, alignment: .trailing)
    }

    @ViewBuilder
    private var quitButton: some View {
        if app.quitPID == nil {
            Image(systemName: "lock.fill")
                .font(.system(size: 9))
                .foregroundStyle(.gray.opacity(0.5))
                .opacity(isHovering ? 1 : 0)
                .help("Part of macOS or another user; can't be quit from here")
        } else if failed {
            Text("Couldn't quit")
                .font(.caption2)
                .foregroundStyle(.orange)
        } else {
            Button {
                if confirming {
                    quit()
                } else {
                    withAnimation(.smooth) { confirming = true }
                    // Disarms by itself, so a stray click later doesn't quit anything
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation(.smooth) { confirming = false }
                    }
                }
            } label: {
                Group {
                    if isQuitting {
                        ProgressView().controlSize(.mini)
                    } else if confirming {
                        Text("Force Quit?")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.gray)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .opacity(isHovering || confirming ? 1 : 0)
            .help("Force quit \(app.name). Unsaved changes are lost.")
        }
    }

    private func quit() {
        isQuitting = true
        Task {
            let done = await monitor.forceQuit(app)
            isQuitting = false
            confirming = false
            if !done {
                withAnimation(.smooth) { failed = true }
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.smooth) { failed = false }
            }
        }
    }
}

#Preview {
    AppsMonitorView()
        .frame(width: 600, height: 150)
        .background(.black)
}
