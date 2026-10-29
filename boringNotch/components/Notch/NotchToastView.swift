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
