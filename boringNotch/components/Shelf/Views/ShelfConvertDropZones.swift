//
//  ShelfConvertDropZones.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension URL {
    /// A path URL for a file reference URL (file:///.file/id=…); other URLs stay as they are
    var filePathURL: URL {
        guard isFileURL, path.hasPrefix("/.file/") else { return self }
        return (self as NSURL).filePathURL ?? self
    }
}

/// What is being dragged over the Shelf, so it can offer conversions as drop targets before the drop
@MainActor
final class ShelfDragState: ObservableObject {
    static let shared = ShelfDragState()

    @Published private(set) var kinds: [ConvertibleKind] = []
    @Published private(set) var fileCount = 0
    @Published private(set) var isActive = false
    /// The tile under the pointer
    @Published var highlighted: String?

    private var targets: Set<String> = []
    private var hideTask: Task<Void, Never>?
    /// Ends the drag state once the mouse button is up: macOS doesn't always report the drag leaving
    /// (the notch closing mid-drag, a drag cancelled elsewhere), and stale tiles would cover the Shelf
    private var watchdog: Task<Void, Never>?
    /// The drag pasteboard is read once per drag, not on every pointer move
    private var readChangeCount = -1

    private init() {}

    var actions: [ConversionAction] {
        Conversions.quickActions(for: kinds, fileCount: fileCount)
    }

    /// True while the pointer is over any of the Shelf's drop targets, whatever is being dragged
    var isTargeted: Bool { !targets.isEmpty }

    func entered(_ id: String, info: DropInfo) {
        targets.insert(id)
        hideTask?.cancel()
        // Only files get conversion tiles; a Shelf item dragged within the Shelf isn't something to convert
        guard !ShelfSelectionModel.shared.isDragging, info.hasItemsConforming(to: [.fileURL]) else { return }
        let pasteboard = NSPasteboard(name: .drag)
        if pasteboard.changeCount != readChangeCount {
            readChangeCount = pasteboard.changeCount
            // The dragged files' names say exactly what they are; the drag's types are only a guess
            let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
                .map(\.filePathURL)
            let kinds = urls.isEmpty ? Self.kinds(in: info) : Self.kinds(ofFiles: urls)
            if kinds != self.kinds { self.kinds = kinds }
            fileCount = max(1, urls.isEmpty ? info.itemProviders(for: [.fileURL]).count : urls.count)
        }
        if !isActive {
            withAnimation(.smooth(duration: 0.2)) { isActive = true }
            watchForDragEnd()
        }
    }

    private func watchForDragEnd() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled else { return }
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    self.finished()
                    return
                }
            }
        }
    }

    static func kinds(ofFiles urls: [URL]) -> [ConvertibleKind] {
        var kinds: [ConvertibleKind] = []
        for url in urls {
            guard let kind = Conversions.kind(ofExtension: url.pathExtension), !kinds.contains(kind) else { continue }
            kinds.append(kind)
        }
        return kinds
    }

    /// Moving from one tile to the next exits one target before entering the other; wait a moment before hiding
    func exited(_ id: String) {
        targets.remove(id)
        if highlighted == id { highlighted = nil }
        guard targets.isEmpty else { return }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self, self.targets.isEmpty else { return }
            withAnimation(.smooth(duration: 0.2)) { self.isActive = false }
        }
    }

    func finished() {
        hideTask?.cancel()
        watchdog?.cancel()
        readChangeCount = -1
        targets = []
        highlighted = nil
        withAnimation(.smooth(duration: 0.2)) { isActive = false }
    }

    private static func droppedFileURL(_ provider: NSItemProvider) async -> URL? {
        if let url = await provider.extractFileURL() { return url }
        if let url = await provider.extractURL(), url.isFileURL { return url }
        if let url = await provider.extractItem(), url.isFileURL { return url }
        return nil
    }

    private static let documentTypes: [UTType] = ["docx", "doc", "dotx", "odt", "rtf", "pages", "xlsx", "xls", "csv", "ods",
                                                  "numbers", "pptx", "ppt", "odp", "key", "html"].compactMap { UTType(filenameExtension: $0) }

    static func kinds(in info: DropInfo) -> [ConvertibleKind] {
        var kinds: [ConvertibleKind] = []
        if info.hasItemsConforming(to: documentTypes) { kinds.append(.document(.text)) }
        if info.hasItemsConforming(to: [.pdf]) { kinds.append(.pdf) }
        if info.hasItemsConforming(to: [.image]) { kinds.append(.image) }
        if info.hasItemsConforming(to: [.movie]) { kinds.append(.video) }
        if info.hasItemsConforming(to: [.audio]) { kinds.append(.audio) }
        return kinds
    }

    /// Converts the dropped files and puts the results on the Shelf; the originals stay where they are
    static func convert(_ providers: [NSItemProvider], with action: ConversionAction) {
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                // Same fallbacks as adding to the Shelf: Finder's drags don't always say "file URL", only "URL"
                if let url = await droppedFileURL(provider) { urls.append(url.filePathURL) }
            }
            guard !urls.isEmpty else {
                FileConversionService.shared.report("The dropped item isn't a file that can be converted.")
                return
            }
            do {
                let results = try await urls.accessSecurityScopedResources { accessible in
                    try await FileConversionService.shared.run(action, on: accessible)
                }
                guard !results.isEmpty else {
                    FileConversionService.shared.report("\(action.title) doesn't work on \(urls.map(\.lastPathComponent).joined(separator: ", ")).")
                    return
                }
                let items = results.compactMap { url -> ShelfItem? in
                    guard let bookmark = try? Bookmark(url: url) else { return nil }
                    return ShelfItem(kind: .file(bookmark: bookmark.data))
                }
                ShelfStateViewModel.shared.add(items)
            } catch {
                // Shown on the Shelf: an alert from an app that isn't frontmost opens behind the user's windows
                FileConversionService.shared.report(error.localizedDescription)
            }
        }
    }
}

/// A drop target that tells ShelfDragState what's over it
struct ShelfDropDelegate: DropDelegate {
    let id: String
    var isTargeted: Binding<Bool>?
    let onDrop: ([NSItemProvider]) -> Bool

    // Targeting comes from all the Shelf's targets together: moving between two of them exits one and
    // enters the other, in either order, and must not look like the drag left (that closes the notch)
    func dropEntered(info: DropInfo) {
        ShelfDragState.shared.entered(id, info: info)
        ShelfDragState.shared.highlighted = id
        isTargeted?.wrappedValue = ShelfDragState.shared.isTargeted
    }

    func dropExited(info: DropInfo) {
        ShelfDragState.shared.exited(id)
        isTargeted?.wrappedValue = ShelfDragState.shared.isTargeted
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted?.wrappedValue = false
        ShelfDragState.shared.finished()
        return onDrop(info.itemProviders(for: [.fileURL, .url, .utf8PlainText, .plainText, .data]))
    }
}

/// Shown over the Shelf while files are dragged onto it: add them as they are, or drop on a conversion
struct ShelfConvertDropZones: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var state = ShelfDragState.shared

    var body: some View {
        // Adding as is: a slim full-width strip on top, so the conversions below get the panel's width to share
        VStack(spacing: 6) {
            tile(id: "add", title: "Add to Shelf", icon: "tray.and.arrow.down.fill", compact: true, onDrop: addToShelf)
                .frame(height: 30)
            HStack(spacing: 6) {
                ForEach(state.actions, id: \.self) { action in
                    tile(id: action.rawValue, title: action.shortTitle, icon: action.icon, compact: false) { providers in
                        vm.dropEvent = true
                        ShelfDragState.convert(providers, with: action)
                        return true
                    }
                    .help(action.title)
                }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Same shape as the panel it covers
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.92)))
        // The gaps between tiles are a target too (adding to the Shelf), so the pointer is never over
        // nothing while the tiles cover the panel
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data],
                delegate: ShelfDropDelegate(id: "zones", isTargeted: $vm.dragDetectorTargeting, onDrop: addToShelf))
    }

    private func addToShelf(_ providers: [NSItemProvider]) -> Bool {
        vm.dropEvent = true
        ShelfStateViewModel.shared.load(providers)
        return true
    }

    /// Equal widths and a fixed frame: a tile that grows when highlighted moves its own edge under the pointer
    private func tile(id: String, title: String, icon: String, compact: Bool,
                      onDrop: @escaping ([NSItemProvider]) -> Bool) -> some View {
        let isOn = state.highlighted == id
        let label = Group {
            Image(systemName: icon)
                .font(.system(size: compact ? 13 : 18, weight: .semibold))
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        return Group {
            if compact {
                HStack(spacing: 6) { label }
            } else {
                VStack(spacing: 5) { label }
            }
        }
        .foregroundStyle(isOn ? .white : .gray)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isOn ? Color.effectiveAccent.opacity(0.45) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isOn ? Color.effectiveAccent : Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
        )
        .animation(.smooth(duration: 0.12), value: isOn)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data],
                delegate: ShelfDropDelegate(id: id, isTargeted: $vm.dragDetectorTargeting, onDrop: onDrop))
    }
}
