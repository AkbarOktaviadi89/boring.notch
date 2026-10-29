//
//  ClipboardHistoryManager.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import AppKit
import Combine
import Defaults

extension ClipEntry: Defaults.Serializable {}

/// Keeps what was copied recently: text in the defaults, images as PNG files beside them.
/// Fed by ClipboardWatcher, which already skips what password managers mark as concealed.
@MainActor
final class ClipboardHistoryManager: ObservableObject {
    static let shared = ClipboardHistoryManager()

    /// Larger images aren't kept
    static let maxImageBytes = 20_000_000

    @Published private(set) var entries: [ClipEntry] = Defaults[.clipboardHistory] {
        didSet { Defaults[.clipboardHistory] = entries }
    }
    @Published var query = ""

    private var thumbnails: [String: NSImage] = [:]

    private init() {}

    var visibleEntries: [ClipEntry] {
        ClipboardHistory.search(entries, query: query)
    }

    static var imageFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("ClipboardHistory", isDirectory: true)
    }

    /// Reads the pasteboard after it changed. Files copied in Finder are skipped: the Shelf is for those.
    func record(_ pasteboard: NSPasteboard, sourceApp: String?) {
        let types = pasteboard.types ?? []
        guard !types.contains(.fileURL) else { return }

        if let text = pasteboard.string(forType: .string) {
            guard ClipboardHistory.shouldKeep(text) else { return }
            add(ClipEntry(text: text, sourceApp: sourceApp))
        } else if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
                  data.count <= Self.maxImageBytes,
                  let image = NSBitmapImageRep(data: data),
                  let png = image.representation(using: .png, properties: [:]) {
            let name = UUID().uuidString + ".png"
            do {
                try FileManager.default.createDirectory(at: Self.imageFolder, withIntermediateDirectories: true)
                try png.write(to: Self.imageFolder.appendingPathComponent(name))
            } catch {
                return
            }
            add(ClipEntry(imageFile: name, imageWidth: image.pixelsWide, imageHeight: image.pixelsHigh, sourceApp: sourceApp))
        }
    }

    private func add(_ entry: ClipEntry) {
        let result = ClipboardHistory.adding(entry, to: entries)
        entries = result.list
        result.removed.forEach(deleteImage)
    }

    /// Puts the entry back on the clipboard and moves it to the top
    func copy(_ entry: ClipEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let text = entry.text {
            pasteboard.setString(text, forType: .string)
        } else if let url = imageURL(entry), let image = NSImage(contentsOf: url) {
            pasteboard.writeObjects([image])
        }
        ClipboardWatcher.shared.ignoreCurrentChange()
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index].copiedAt = Date()
        }
    }

    func togglePin(_ entry: ClipEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isPinned.toggle()
    }

    func delete(_ entry: ClipEntry) {
        entries.removeAll { $0.id == entry.id }
        deleteImage(entry)
    }

    /// Pinned entries stay
    func clearUnpinned() {
        let removed = entries.filter { !$0.isPinned }
        entries.removeAll { !$0.isPinned }
        removed.forEach(deleteImage)
    }

    func clearAll() {
        entries.forEach(deleteImage)
        entries = []
    }

    func imageURL(_ entry: ClipEntry) -> URL? {
        entry.imageFile.map { Self.imageFolder.appendingPathComponent($0) }
    }

    func thumbnail(_ entry: ClipEntry) -> NSImage? {
        guard let file = entry.imageFile else { return nil }
        if let cached = thumbnails[file] { return cached }
        guard let url = imageURL(entry),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 96,
              ] as CFDictionary)
        else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbnails[file] = image
        return image
    }

    private func deleteImage(_ entry: ClipEntry) {
        guard let url = imageURL(entry) else { return }
        try? FileManager.default.removeItem(at: url)
        thumbnails[entry.imageFile ?? ""] = nil
    }
}
