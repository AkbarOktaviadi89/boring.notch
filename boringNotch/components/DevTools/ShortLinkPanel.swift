//
//  ShortLinkPanel.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import SwiftUI
import UniformTypeIdentifiers

/// The Link tool's output: the short link with its QR code, warnings, and the recent links
struct ShortLinkPanel: View {
    @ObservedObject var links = ShortLinkManager.shared
    @ObservedObject var tools = DevToolsManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            main
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if !links.history.isEmpty {
                history
                    .frame(width: 190)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
        // About 80 pt are left under the tool row; nothing in here may draw over the tool chips above
        .clipped()
    }

    // MARK: - Result

    @ViewBuilder
    private var main: some View {
        if let warning = links.warning {
            VStack(alignment: .leading, spacing: 4) {
                Label("This link may contain a secret", systemImage: "exclamationmark.shield.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Text("\(warning.reason) Anyone with the short link could open it.")
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    pill("Shorten anyway", icon: "link", tint: .orange) {
                        Task { await links.shorten(warning.url.absoluteString, confirmed: true) }
                    }
                    pill("Cancel") { links.dismissMessages() }
                }
            }
        } else if let error = links.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(3)
        } else if links.isWorking {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Shortening…")
                    .font(.callout)
                    .foregroundStyle(.gray)
            }
        } else if let record = links.current {
            result(record)
        } else {
            Text("Paste a long link and press Shorten. The short link is copied for you, with a QR code to scan.")
                .font(.caption)
                .foregroundStyle(.gray.opacity(0.7))
                .lineLimit(3)
        }
    }

    private func result(_ record: ShortLinkRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let qr = links.qrCode(for: record.short) {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 58, height: 58)
                    .padding(3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white))
                    // Drag it into a document, a chat or the Shelf
                    .onDrag { NSItemProvider(object: qr) }
                    .help("QR code for \(record.short). Drag it anywhere.")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(record.short)
                    .font(.system(.headline, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                // The fallback notice takes the original link's line, so the block keeps its height
                if let notice = links.notice {
                    Text(notice)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(notice)
                } else {
                    Text(record.original)
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(record.original)
                }
                HStack(spacing: 6) {
                    pill(links.didCopy ? "Copied" : "Copy", icon: links.didCopy ? "checkmark" : "doc.on.doc", tint: .effectiveAccent) {
                        links.copy(record)
                    }
                    pill("Open", icon: "safari") {
                        if let url = URL(string: record.short) { NSWorkspace.shared.open(url) }
                    }
                    Text(record.service.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
            }
        }
    }

    // MARK: - History

    private var history: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Recent")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.gray)
                Spacer()
                Button("Clear") { withAnimation(.smooth) { links.clearHistory() } }
                    .buttonStyle(PlainButtonStyle())
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(links.history) { record in
                        HistoryRow(record: record, isCurrent: record.id == links.current?.id)
                    }
                }
            }
            .allowsScrollingInOpenNotch()
        }
    }

    private func pill(_ title: LocalizedStringKey, icon: String? = nil, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.system(.caption, design: .rounded, weight: tint == nil ? .regular : .semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint ?? Color(nsColor: .secondarySystemFill)))
            .foregroundStyle(.white)
        }
        .buttonStyle(PlainButtonStyle())
        .fixedSize()
    }
}

private struct HistoryRow: View {
    let record: ShortLinkRecord
    let isCurrent: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button {
                ShortLinkManager.shared.show(record)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(record.short.replacingOccurrences(of: "https://", with: ""))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(record.original.replacingOccurrences(of: "https://", with: ""))
                        .font(.caption2)
                        .foregroundStyle(.gray)
                        .truncationMode(.middle)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            if isHovering {
                Button { ShortLinkManager.shared.copy(record) } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 10))
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundStyle(.gray)
                .help("Copy")
                Button { withAnimation(.smooth) { ShortLinkManager.shared.remove(record) } } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundStyle(.gray)
                .help("Remove from history")
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isCurrent ? Color.white.opacity(0.12) : isHovering ? Color.white.opacity(0.06) : .clear)
        )
        .onHover { isHovering = $0 }
    }
}
