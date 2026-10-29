//
//  FoldersManager.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import AppKit
import Combine
import Defaults

extension PinnedFolder: Defaults.Serializable {}

/// The Folders panel: folders opened often lately (Spotlight, read by the helper) and folders the user pinned
@MainActor
final class FoldersManager: ObservableObject {
    static let shared = FoldersManager()

    @Published private(set) var pinned: [PinnedFolder] = Defaults[.pinnedFolders] {
        didSet { Defaults[.pinnedFolders] = pinned }
    }
    @Published private(set) var hidden: [String] = Defaults[.hiddenFolders] {
        didSet { Defaults[.hiddenFolders] = hidden }
    }
    @Published private(set) var spotlight: [FolderUsage] = []
    @Published private(set) var isLoading = false
    @Published var query = ""
    /// "Copied 2 files to dpr", or why not
    @Published private(set) var message: String?

    private var messageTask: Task<Void, Never>?

    private init() {}

    static var home: String {
        getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
    }

    var rows: [ListedFolder] {
        let own = Defaults[.folderOpens].compactMap { path, value -> FolderUsage? in
            guard value.count == 2 else { return nil }
            return FolderUsage(path: path, lastUsed: Date(timeIntervalSince1970: value[1]), useCount: Int(value[0]))
        }
        return FolderRanking.list(pinned: pinned.map(\.path), usage: FolderRanking.merge(spotlight, own),
                                  hidden: Set(hidden), home: Self.home, now: Date(), query: query)
    }

    func refresh() async {
        isLoading = spotlight.isEmpty
        defer { isLoading = false }
        if let report = await XPCHelperClient.shared.recentFoldersReport(days: FolderRanking.lookbackDays) {
            spotlight = FolderRanking.parse(report)
        }
    }

    // MARK: - Opening

    func open(_ folder: ListedFolder) async -> Bool {
        recordOpen(folder.path)
        if let url = resolvedURL(folder.path) {
            let opened = url.accessSecurityScopedResource { NSWorkspace.shared.open($0) }
            if opened { return true }
        }
        // Folders without a bookmark are opened by the helper; the sandbox doesn't let the app reach them
        return await XPCHelperClient.shared.openFolder(folder.path)
    }

    private func recordOpen(_ path: String) {
        var opens = Defaults[.folderOpens]
        let count = (opens[path]?.first ?? 0) + 1
        opens[path] = [count, Date().timeIntervalSince1970]
        Defaults[.folderOpens] = opens
        objectWillChange.send()
    }

    // MARK: - Pinning and removing

    func isPinned(_ path: String) -> Bool {
        pinned.contains { $0.path == path }
    }

    /// Pins without asking for access; access is asked for the first time files are dropped into it
    func pin(_ path: String, bookmark: Data? = nil) {
        hidden.removeAll { $0 == path }
        if let index = pinned.firstIndex(where: { $0.path == path }) {
            if let bookmark { pinned[index] = PinnedFolder(path: path, bookmark: bookmark) }
            return
        }
        pinned.append(PinnedFolder(path: path, bookmark: bookmark))
    }

    func unpin(_ path: String) {
        pinned.removeAll { $0.path == path }
    }

    /// Pinned folders are unpinned; folders from the automatic list are hidden so they don't come back
    func remove(_ folder: ListedFolder) {
        if folder.isPinned {
            unpin(folder.path)
        } else if !hidden.contains(folder.path) {
            hidden.append(folder.path)
        }
    }

    func restoreHidden() {
        hidden = []
    }

    /// Folders dragged onto the panel are pinned, with access from the drag
    func pinDropped(_ urls: [URL]) {
        for url in urls where (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            pin(url.path, bookmark: try? url.bookmarkData(options: .withSecurityScope))
        }
    }

    /// The "+" button: pick folders to pin
    func choose() {
        SharingStateManager.shared.beginInteraction()
        defer {
            SharingStateManager.shared.endInteraction()
        }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Pin"
        panel.message = "Choose folders to keep at the top of the Folders panel"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            pin(url.path, bookmark: try? url.bookmarkData(options: .withSecurityScope))
        }
    }

    // MARK: - Dropping files into a folder

    /// Copies, never moves: the originals stay where they are
    func copy(_ files: [URL], into folder: ListedFolder) {
        guard let destination = accessibleURL(for: folder.path) else {
            report("Boring Notch needs access to \(folder.name) to put files there.")
            return
        }
        let copied = destination.accessSecurityScopedResource { folderURL -> Int in
            var count = 0
            for file in files {
                let name = Conversions.uniqueName(file.lastPathComponent) {
                    FileManager.default.fileExists(atPath: folderURL.appendingPathComponent($0).path)
                }
                if (try? file.accessSecurityScopedResource { try FileManager.default.copyItem(at: $0, to: folderURL.appendingPathComponent(name)) }) != nil {
                    count += 1
                }
            }
            return count
        }
        report(copied == files.count
               ? "Copied \(copied == 1 ? "1 file" : "\(copied) files") to \(folder.name)"
               : "Copied \(copied) of \(files.count) to \(folder.name)")
        if copied > 0 { recordOpen(folder.path) }
    }

    /// The folder's bookmark, or one from asking the user once (and then the folder is pinned with it)
    private func accessibleURL(for path: String) -> URL? {
        if let url = resolvedURL(path) { return url }
        SharingStateManager.shared.beginInteraction()
        defer { SharingStateManager.shared.endInteraction() }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: path)
        panel.prompt = "Allow"
        panel.message = "Allow Boring Notch to put files in “\((path as NSString).lastPathComponent)”. It's asked once; the folder is pinned."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        pin(url.path, bookmark: try? url.bookmarkData(options: .withSecurityScope))
        return url
    }

    private func resolvedURL(_ path: String) -> URL? {
        guard let data = pinned.first(where: { $0.path == path })?.bookmark else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    func report(_ text: String) {
        message = text
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}
