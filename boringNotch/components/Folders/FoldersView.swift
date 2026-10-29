//
//  FoldersView.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import SwiftUI
import UniformTypeIdentifiers

/// Opened with ⌃⌥⌘F: folders opened often lately and pinned ones. Click to open in Finder,
/// drop files on a folder to copy them there, drop folders on the panel to pin them.
struct FoldersView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var folders = FoldersManager.shared
    @State private var selectedID: String?
    @State private var panelTargeted = false
    @FocusState private var searchFocused: Bool

    private var rows: [ListedFolder] { folders.rows }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    TextField("Search folders", text: $folders.query)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .focused($searchFocused)
                        .onSubmit { if let row = selectedRow { open(row) } }
                        .onExitCommand(perform: close)
                        .onKeyPress(.downArrow) { move(1); return .handled }
                        .onKeyPress(.upArrow) { move(-1); return .handled }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color(nsColor: .secondarySystemFill)))

                Button { folders.choose() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color(nsColor: .secondarySystemFill)))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Pin folders (or drag folders here)")
            }

            if folders.isLoading && rows.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                Text(folders.query.isEmpty ? "No folders yet. Open some in Finder, press +, or drag folders here." : "No matches")
                    .font(.callout)
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 4) {
                            ForEach(rows) { row in
                                FolderRow(folder: row, isSelected: row.id == selectedRow?.id) { open(row) }
                                    .id(row.id)
                            }
                        }
                    }
                    .allowsScrollingInOpenNotch()
                    .onChange(of: selectedID) { _, id in
                        if let id { withAnimation(.smooth) { proxy.scrollTo(id) } }
                    }
                }
            }

            Group {
                if let message = folders.message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("↩ open · drop files on a folder to copy them there · drag a folder in to pin it")
                        .foregroundStyle(.gray.opacity(0.7))
                }
            }
            .font(.caption2)
            .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(panelTargeted ? Color.effectiveAccent : .clear, style: StrokeStyle(lineWidth: 2, dash: [6]))
        )
        // Folders dropped anywhere but on a row are pinned
        .onDrop(of: [.fileURL], isTargeted: $panelTargeted) { providers in
            vm.dropEvent = true
            Task {
                let urls = await FolderRow.fileURLs(from: providers)
                folders.pinDropped(urls)
            }
            return true
        }
        .acceptsNotchKeyboardInput()
        .onAppear {
            folders.query = ""
            selectedID = nil
            Task { await folders.refresh() }
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                NotchKeyboardFocus.takeKeyboard()
                searchFocused = true
            }
        }
        .onChange(of: folders.query) { selectedID = nil }
    }

    private var selectedRow: ListedFolder? {
        rows.first { $0.id == selectedID } ?? rows.first
    }

    /// Two columns: left and right move by one, up and down by a row, through the arrow keys' up and down
    private func move(_ step: Int) {
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == selectedRow?.id } ?? 0
        selectedID = rows[min(max(current + step * 2, 0), rows.count - 1)].id
    }

    private func open(_ folder: ListedFolder) {
        Task {
            _ = await folders.open(folder)
            close()
        }
    }

    private func close() {
        NotchKeyboardFocus.returnKeyboard()
        vm.close()
    }
}

private struct FolderRow: View {
    @EnvironmentObject var vm: BoringViewModel
    let folder: ListedFolder
    let isSelected: Bool
    let open: () -> Void
    @ObservedObject var folders = FoldersManager.shared
    @State private var isHovering = false
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isTargeted ? "folder.fill.badge.plus" : "folder.fill")
                .font(.system(size: 15))
                .foregroundStyle(folder.isPinned ? Color.effectiveAccent : Color(red: 0.36, green: 0.68, blue: 0.98))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 0) {
                Text(folder.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(FolderRanking.displayParent(of: folder.path, home: FoldersManager.home))
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovering || folder.isPinned {
                Button {
                    withAnimation(.smooth) {
                        folder.isPinned ? folders.unpin(folder.path) : folders.pin(folder.path)
                    }
                } label: {
                    Image(systemName: folder.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(folder.isPinned ? Color.effectiveAccent : .gray)
                }
                .buttonStyle(PlainButtonStyle())
                .help(folder.isPinned ? "Unpin" : "Pin: always at the top")
            }
            if isHovering {
                Button { withAnimation(.smooth) { folders.remove(folder) } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.gray)
                }
                .buttonStyle(PlainButtonStyle())
                .help(folder.isPinned ? "Unpin and remove" : "Remove from the list")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isTargeted ? Color.effectiveAccent.opacity(0.35)
                      : isSelected ? Color.white.opacity(0.12)
                      : isHovering ? Color.white.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { isHovering = $0 }
        .help(folder.path)
        // Files dropped on a folder are copied into it
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            vm.dropEvent = true
            Task {
                let urls = await Self.fileURLs(from: providers)
                guard !urls.isEmpty else { return }
                folders.copy(urls, into: folder)
            }
            return true
        }
    }

    static func fileURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let url = await provider.extractFileURL() {
                urls.append(url.filePathURL)
            } else if let url = await provider.extractURL(), url.isFileURL {
                urls.append(url.filePathURL)
            }
        }
        return urls
    }
}
