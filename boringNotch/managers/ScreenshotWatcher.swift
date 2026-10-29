//
//  ScreenshotWatcher.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-30.
//

import AppKit
import Combine
import Defaults

/// Puts each new screenshot and screen recording on the Shelf, ready to drag into a chat or a document.
/// Watches the folder macOS saves them to with a file system event source, so nothing polls.
@MainActor
final class ScreenshotWatcher: ObservableObject {
    static let shared = ScreenshotWatcher()

    /// The screenshot folder, when it's somewhere the app may only read after the user allows it once
    @Published private(set) var needsAccessTo: String?
    @Published private(set) var watchedFolder: String?

    private var source: DispatchSourceFileSystemObject?
    private var accessedURL: URL?
    private var known: Set<String> = []
    private var scanTask: Task<Void, Never>?
    private var settingsTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard settingsTask == nil else { return }
        settingsTask = Task { [weak self] in
            for await enabled in Defaults.updates(.screenshotsToShelf) {
                self?.stop()
                if enabled { await self?.begin() }
            }
        }
    }

    /// Reads the location again; Screenshot.app's Options › Save to may have changed it
    func restart() {
        stop()
        guard Defaults[.screenshotsToShelf] else { return }
        Task { await begin() }
    }

    private func begin() async {
        guard let path = await XPCHelperClient.shared.screenshotLocation() else { return }
        var folder = URL(fileURLWithPath: path, isDirectory: true)
        if !Self.isReachableWithoutAsking(path) {
            guard let granted = grantedURL(for: path), granted.startAccessingSecurityScopedResource() else {
                needsAccessTo = path
                return
            }
            accessedURL = granted
            folder = granted
        }
        needsAccessTo = nil
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        known = Set(names(in: folder))
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            // A save shows up as several writes; look once they've settled
            self?.scanTask?.cancel()
            self?.scanTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                self?.scan(folder)
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        watchedFolder = path
    }

    func stop() {
        source?.cancel()
        source = nil
        scanTask?.cancel()
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
        watchedFolder = nil
    }

    /// Pictures and Downloads are covered by the app's entitlements; other folders need the user's say-so once
    static func isReachableWithoutAsking(_ path: String) -> Bool {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return [home + "/Pictures", home + "/Downloads"].contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// Settings › "Allow access…": a folder picker opened on the screenshot folder
    func requestAccess() {
        guard let path = needsAccessTo else { return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: path)
        panel.prompt = "Allow"
        panel.message = "Allow Boring Notch to see new screenshots in this folder, to put them on the Shelf."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Defaults[.screenshotFolderBookmark] = try? url.bookmarkData(options: .withSecurityScope)
        restart()
    }

    private func grantedURL(for path: String) -> URL? {
        guard let data = Defaults[.screenshotFolderBookmark] else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
              url.path == path else { return nil }
        return url
    }

    private func names(in folder: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    }

    private func scan(_ folder: URL) {
        let current = names(in: folder)
        let new = current.filter { !known.contains($0) && !$0.hasPrefix(".") }
        known = Set(current)
        let screenshots = new
            .map { folder.appendingPathComponent($0) }
            .filter(Self.isScreenCapture)
        guard !screenshots.isEmpty else { return }
        let items = screenshots.compactMap { url -> ShelfItem? in
            guard let bookmark = try? Bookmark(url: url) else { return nil }
            return ShelfItem(kind: .file(bookmark: bookmark.data))
        }
        ShelfStateViewModel.shared.add(items)
        BoringViewCoordinator.shared.showToast(icon: "camera.viewfinder", title: "Screenshot",
                                               detail: items.count == 1 ? "on the Shelf" : "\(items.count) on the Shelf", tint: .green)
    }

    /// macOS marks what screencapture writes, so other files saved in the same folder (often the Desktop) stay out
    static func isScreenCapture(_ url: URL) -> Bool {
        // Screenshots carry IsScreenCapture, screen recordings IsScreenRecording; both carry the capture type
        ["kMDItemIsScreenCapture", "kMDItemIsScreenRecording", "kMDItemScreenCaptureType"].contains { key in
            getxattr(url.path, "com.apple.metadata:" + key, nil, 0, 0, 0) > 0
        }
    }
}

