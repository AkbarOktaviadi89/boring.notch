//
//  MonitorView.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Defaults
import SwiftUI

enum MonitorSection: String, CaseIterable, Identifiable, Defaults.Serializable {
    case system = "System"
    case apps = "Apps"
    case servers = "Servers"

    var id: Self { self }
}

/// The Monitor tab: system stats and local dev servers share one tab so the tab row still fits beside the notch
struct MonitorView: View {
    @Default(.monitorSection) var section

    var body: some View {
        switch section {
        case .system:
            SystemMonitorView()
        case .apps:
            AppsMonitorView()
        case .servers:
            DevServersView()
        }
    }
}

/// System | Servers switch, shown at the start of each section's header
struct MonitorSectionPicker: View {
    @Default(.monitorSection) var section

    var body: some View {
        CapsuleSegmentedPicker(options: MonitorSection.allCases, selection: $section, title: \.rawValue)
    }
}

/// Small segmented control for switching between the sections of a notch tab
struct CapsuleSegmentedPicker<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(.smooth) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(selection == option ? Color.white.opacity(0.2) : .clear))
                        .foregroundStyle(selection == option ? .white : .gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(2)
        .background(Capsule().fill(Color(nsColor: .secondarySystemFill)))
    }
}

struct SystemMonitorView: View {
    @ObservedObject var monitor = SystemMonitor.shared

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    MonitorSectionPicker()
                    Spacer()
                    thermalBadge
                }
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        cpuCard
                        memoryCard
                    }
                    GridRow {
                        networkCard
                        diskCard
                    }
                }
            }
            .frame(width: 320)

            topProcessesList
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { monitor.startMonitoring() }
        .onDisappear { monitor.stopMonitoring() }
    }

    // MARK: - Cards

    private var cpuCard: some View {
        StatCard(title: "CPU", icon: "cpu") {
            Text(monitor.cpuUsage.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle((monitor.cpuUsage ?? 0) > 0.8 ? .orange : .white)
        } background: {
            Sparkline(values: monitor.cpuHistory, capacity: SystemMonitor.historyLength)
                .stroke(Color.effectiveAccent.opacity(0.7), lineWidth: 1.5)
                .padding(.top, 18)
        }
    }

    private var memoryCard: some View {
        let fraction = monitor.memoryTotal > 0 ? Double(monitor.memoryUsed) / Double(monitor.memoryTotal) : 0
        return StatCard(title: "Memory", icon: "memorychip") {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(SystemStats.formatBytes(monitor.memoryUsed, base: 1024)) / \(SystemStats.formatBytes(monitor.memoryTotal, base: 1024))")
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                UsageBar(fraction: fraction)
            }
        }
    }

    private var networkCard: some View {
        StatCard(title: "Network", icon: "arrow.up.arrow.down") {
            VStack(alignment: .leading, spacing: 0) {
                Text("↓ \(monitor.downloadRate.map(SystemStats.formatRate) ?? "–")")
                Text("↑ \(monitor.uploadRate.map(SystemStats.formatRate) ?? "–")")
                    .foregroundStyle(.gray)
            }
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .monospacedDigit()
        }
    }

    private var diskCard: some View {
        let fraction: Double = {
            guard let free = monitor.diskFree, let total = monitor.diskTotal, total > 0 else { return 0 }
            return 1 - Double(free) / Double(total)
        }()
        return StatCard(title: "Disk", icon: "internaldrive") {
            VStack(alignment: .leading, spacing: 3) {
                Text(monitor.diskFree.map { "\(SystemStats.formatBytes($0, base: 1000)) free" } ?? "–")
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                UsageBar(fraction: fraction)
            }
        }
    }

    @ViewBuilder
    private var thermalBadge: some View {
        switch monitor.thermalState {
        case .nominal:
            EmptyView()
        case .fair:
            badge("Warm", color: .yellow)
        case .serious:
            badge("Hot", color: .orange)
        case .critical:
            badge("Critical heat", color: .red)
        @unknown default:
            EmptyView()
        }
    }

    private func badge(_ text: LocalizedStringKey, color: Color) -> some View {
        Label(text, systemImage: "thermometer.medium")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .help("Thermal state reported by macOS; the Mac may slow down to cool off")
    }

    // MARK: - Top processes

    private var topProcessesList: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Top processes")
                .font(.caption)
                .foregroundStyle(.gray)
                .frame(height: 24)
            if monitor.topProcesses.isEmpty {
                Text("Loading…")
                    .font(.caption)
                    .foregroundStyle(.gray.opacity(0.6))
            }
            ForEach(monitor.topProcesses) { process in
                HStack(spacing: 6) {
                    Text(process.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help("\(process.name) (pid \(String(process.pid)))")
                    Spacer(minLength: 4)
                    Text(String(format: "%.0f%%", process.cpuPercent))
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundStyle(process.cpuPercent > 80 ? .orange : .white)
                    Text(SystemStats.formatBytes(process.memoryBytes, base: 1024))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.gray)
                        .frame(width: 48, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct StatCard<Content: View, Background: View>: View {
    let title: LocalizedStringKey
    let icon: String
    @ViewBuilder let content: Content
    @ViewBuilder let background: Background

    init(
        title: LocalizedStringKey,
        icon: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder background: () -> Background = { EmptyView() }
    ) {
        self.title = title
        self.icon = icon
        self.content = content()
        self.background = background()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.gray)
            content
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
        .background(background)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct UsageBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(fraction > 0.85 ? Color.orange : Color.effectiveAccent)
                    .frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 4)
        .animation(.smooth, value: fraction)
    }
}

/// Line chart of values in 0...1, right-aligned so new samples enter from the right
private struct Sparkline: Shape {
    let values: [Double]
    let capacity: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1, capacity > 1 else { return path }
        let step = rect.width / CGFloat(capacity - 1)
        let startX = rect.maxX - step * CGFloat(values.count - 1)
        for (index, value) in values.enumerated() {
            let point = CGPoint(
                x: startX + step * CGFloat(index),
                y: rect.maxY - rect.height * CGFloat(min(1, max(0, value)))
            )
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }
}

#Preview {
    MonitorView()
        .frame(width: 600, height: 150)
        .background(.black)
}
