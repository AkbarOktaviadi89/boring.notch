//
//  NotchToastView.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import SwiftUI

/// Shown on the closed notch for a few seconds after a background action, like "Copied · 42 words"
struct NotchToastView: View {
    @EnvironmentObject var vm: BoringViewModel
    let toast: NotchToast

    static let sideWidth: CGFloat = 96

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                Image(systemName: toast.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(toast.tint)
                Text(toast.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: Self.sideWidth)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + -cornerRadiusInsets.closed.top)

            Text(toast.detail)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: Self.sideWidth)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

/// On the closed notch while Shelf files are being converted
struct ConvertingLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    let status: String

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Converting")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: NotchToastView.sideWidth)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + -cornerRadiusInsets.closed.top)

            Text(status.replacingOccurrences(of: "Converting ", with: "").replacingOccurrences(of: "…", with: ""))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: NotchToastView.sideWidth)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .help(status)
    }
}

/// On the closed notch while files download into ~/Downloads
struct DownloadLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    let downloads: [DownloadProgressWatcher.ActiveDownload]

    private var fraction: Double { DownloadNaming.overall(downloads.map(\.fraction)) }

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.15), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(Color.effectiveAccent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.3), value: fraction)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .frame(width: 15, height: 15)
                Text(downloads.count == 1 ? downloads[0].name : "\(downloads.count) files")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: NotchToastView.sideWidth)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + -cornerRadiusInsets.closed.top)

            Text(DownloadNaming.percent(fraction))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: NotchToastView.sideWidth)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .help(downloads.map(\.name).joined(separator: "\n"))
    }
}
