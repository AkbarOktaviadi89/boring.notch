//
//  ClipboardHistoryView.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import SwiftUI

/// Opened with ⌃⌥⌘V: search what was copied, pick one, and it's on the clipboard again, ready for ⌘V
struct ClipboardHistoryView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var history = ClipboardHistoryManager.shared
    @State private var selectedID: ClipEntry.ID?
    @FocusState private var searchFocused: Bool

    private var entries: [ClipEntry] { history.visibleEntries }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    TextField("Search what you copied", text: $history.query)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .focused($searchFocused)
                        .onSubmit { if let entry = selectedEntry { pick(entry) } }
                        .onExitCommand(perform: close)
                        .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color(nsColor: .secondarySystemFill)))

                Text("\(entries.count)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.gray)
                Menu {
                    Button("Clear unpinned") { withAnimation(.smooth) { history.clearUnpinned() } }
                    Button("Clear everything") { withAnimation(.smooth) { history.clearAll() } }
                } label: {
                    Image(systemName: "trash")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.gray)
                .help("Clear history")
            }

            if entries.isEmpty {
                Text(history.query.isEmpty ? "Nothing copied yet. Copy some text or an image and it shows up here." : "No matches")
                    .font(.callout)
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 1) {
                            ForEach(entries) { entry in
                                ClipRow(entry: entry, isSelected: entry.id == selectedEntry?.id) { pick(entry) }
                                    .id(entry.id)
                            }
                        }
                    }
                    .allowsScrollingInOpenNotch()
                    .onChange(of: selectedID) { _, id in
                        if let id { withAnimation(.smooth) { proxy.scrollTo(id) } }
                    }
                }
            }

            Text("↩ copy · ↑↓ choose · esc close — then ⌘V where you want it")
                .font(.caption2)
                .foregroundStyle(.gray.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .acceptsNotchKeyboardInput()
        .onAppear {
            history.query = ""
            selectedID = nil
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                NotchKeyboardFocus.takeKeyboard()
                searchFocused = true
            }
        }
        .onChange(of: history.query) { selectedID = nil }
    }

    /// The highlighted row, the first one until the arrows move it
    private var selectedEntry: ClipEntry? {
        entries.first { $0.id == selectedID } ?? entries.first
    }

    private func moveSelection(_ step: Int) {
        guard !entries.isEmpty else { return }
        let current = entries.firstIndex { $0.id == selectedEntry?.id } ?? 0
        selectedID = entries[min(max(current + step, 0), entries.count - 1)].id
    }

    private func pick(_ entry: ClipEntry) {
        history.copy(entry)
        close()
    }

    private func close() {
        NotchKeyboardFocus.returnKeyboard()
        vm.close()
    }
}

private struct ClipRow: View {
    let entry: ClipEntry
    let isSelected: Bool
    let pick: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            leading
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(entry.isLink ? .system(.callout, design: .monospaced) : .callout)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if entry.isPinned || isHovering {
                Button { withAnimation(.smooth) { ClipboardHistoryManager.shared.togglePin(entry) } } label: {
                    Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                        .foregroundStyle(entry.isPinned ? Color.effectiveAccent : .gray)
                }
                .buttonStyle(PlainButtonStyle())
                .help(entry.isPinned ? "Unpin" : "Pin: kept when the history fills up or is cleared")
            }
            if isHovering {
                Button { withAnimation(.smooth) { ClipboardHistoryManager.shared.delete(entry) } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.gray)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Remove")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.white.opacity(0.12) : isHovering ? Color.white.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: pick)
        .onHover { isHovering = $0 }
        .help(entry.text.map { ClipboardHistory.preview($0, length: 600) } ?? "")
    }

    @ViewBuilder
    private var leading: some View {
        if let thumbnail = ClipboardHistoryManager.shared.thumbnail(entry) {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: entry.isLink ? "link" : entry.isImage ? "photo" : "doc.plaintext")
                .font(.system(size: 13))
                .foregroundStyle(.gray)
        }
    }

    private var title: String {
        if let text = entry.text { return ClipboardHistory.preview(text) }
        return "Image"
    }

    private var detail: String {
        var parts: [String] = []
        if let width = entry.imageWidth, let height = entry.imageHeight { parts.append("\(width)×\(height)") }
        if let app = entry.sourceApp { parts.append(app) }
        parts.append(entry.copiedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
        return parts.joined(separator: " · ")
    }
}
