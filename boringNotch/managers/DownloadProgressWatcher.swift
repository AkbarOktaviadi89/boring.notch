//
//  DownloadProgressWatcher.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-30.
//

import AppKit
import Combine
import Defaults

/// Follows downloads into ~/Downloads through the same file progress that draws Finder's progress bars
/// (Safari, Chrome and others publish it), shows it on the closed notch and puts finished files on the Shelf
@MainActor
final class DownloadProgressWatcher: ObservableObject {
    static let shared = DownloadProgressWatcher()

    struct ActiveDownload: Identifiable, Equatable {
        let id: UUID
        var name: String
        var fraction: Double
        /// Where the browser writes while downloading, used to find the finished file
        var partialURL: URL?
    }

    @Published private(set) var active: [ActiveDownload] = []

    private var subscriber: Any?
    private var observations: [UUID: NSKeyValueObservation] = [:]
    private var settingsTask: Task<Void, Never>?

    private init() {}

    static var downloadsFolder: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Downloads", isDirectory: true)
    }

    func start() {
        guard settingsTask == nil else { return }
        settingsTask = Task { [weak self] in
            for await (onNotch, toShelf) in Defaults.updates(.downloadsOnNotch, .downloadsToShelf) {
                self?.setWatching(onNotch || toShelf)
            }
        }
    }

    private func setWatching(_ on: Bool) {
        if on, subscriber == nil {
            subscriber = Progress.addSubscriber(forFileURL: Self.downloadsFolder) { [weak self] progress in
                let id = UUID()
                Task { @MainActor in self?.track(progress, id: id) }
                return {
                    Task { @MainActor in self?.finish(id, progress: progress) }
                }
            }
        } else if !on, let subscriber {
            Progress.removeSubscriber(subscriber)
            self.subscriber = nil
            observations.removeAll()
            active = []
        }
    }

    private func track(_ progress: Progress, id: UUID) {
        // Only downloads, not other apps copying files into the folder
        if let kind = progress.fileOperationKind, kind != .downloading { return }
        let url = progress.fileURL
        let rawName = url?.lastPathComponent ?? "Download"
        let name = DownloadNaming.finalName(rawName) ?? "Download"
        active.append(ActiveDownload(id: id, name: name, fraction: progress.fractionCompleted, partialURL: url))
        // Progress changes very often; the notch only needs a whole percent
        observations[id] = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in
                guard let self, let index = self.active.firstIndex(where: { $0.id == id }) else { return }
                if Int(fraction * 100) != Int(self.active[index].fraction * 100) {
                    self.active[index].fraction = fraction
                }
            }
        }
    }

    private func finish(_ id: UUID, progress: Progress) {
        observations[id] = nil
        guard let index = active.firstIndex(where: { $0.id == id }) else { return }
        let download = active.remove(at: index)
        guard !progress.isCancelled else { return }
        // The browser renames the partial file once done; give it a moment
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard let finished = finishedFile(for: download) else { return }
            if Defaults[.downloadsToShelf], let bookmark = try? Bookmark(url: finished) {
                ShelfStateViewModel.shared.add([ShelfItem(kind: .file(bookmark: bookmark.data))])
            }
            if Defaults[.downloadsOnNotch] {
                BoringViewCoordinator.shared.showToast(icon: "arrow.down.circle.fill", title: "Downloaded",
                                                       detail: finished.lastPathComponent, tint: .green)
            }
        }
    }

    private func finishedFile(for download: ActiveDownload) -> URL? {
        let folder = Self.downloadsFolder
        if let partial = download.partialURL, !DownloadNaming.isPartial(partial.lastPathComponent),
           FileManager.default.fileExists(atPath: partial.path) {
            return partial
        }
        let candidate = folder.appendingPathComponent(download.name)
        if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        // The name wasn't known while downloading ("Unconfirmed …"): take the newest finished file
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return files
            .filter { !$0.lastPathComponent.hasPrefix(".") && !DownloadNaming.isPartial($0.lastPathComponent) }
            .max { ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
            .flatMap { url in
                let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return Date().timeIntervalSince(created) < 120 ? url : nil
            }
    }
}
