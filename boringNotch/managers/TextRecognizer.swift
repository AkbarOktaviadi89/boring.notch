//
//  TextRecognizer.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import AppKit
import PDFKit
import Vision

/// On-device OCR with Vision, in Indonesian and English
enum TextRecognizer {
    /// Scanned PDFs longer than this only have their first pages read
    static let maxPDFPages = 30

    static func text(in image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["id-ID", "en-US"]
            try VNImageRequestHandler(cgImage: image).perform([request])
            let fragments = (request.results ?? []).compactMap { observation -> RecognizedFragment? in
                guard let best = observation.topCandidates(1).first else { return nil }
                let box = observation.boundingBox
                return RecognizedFragment(text: best.string, x: box.minX, y: box.minY, width: box.width, height: box.height)
            }
            return TextLayout.join(fragments)
        }.value
    }

    /// Images are read with OCR. PDFs give their own text when they have it; scanned ones are read page by page.
    static func text(inFile url: URL) async throws -> String {
        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: url) else { throw ConversionError.unreadable(url.lastPathComponent) }
            if let embedded = document.string, !embedded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return embedded
            }
            var pages: [String] = []
            for index in 0..<min(document.pageCount, maxPDFPages) {
                guard let page = document.page(at: index) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                let thumbnail = page.thumbnail(of: NSSize(width: bounds.width * 2, height: bounds.height * 2), for: .mediaBox)
                guard let image = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
                let text = try await text(in: image)
                if !text.isEmpty { pages.append(text) }
            }
            return pages.joined(separator: "\n\n")
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ConversionError.unreadable(url.lastPathComponent)
        }
        return try await text(in: image)
    }
}

/// ⌃⌥⌘T: select part of the screen, and the text in it is on the clipboard
@MainActor
enum ScreenText {
    static func captureAndCopy() async {
        // Without Screen Recording access the capture only shows the wallpaper
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            BoringViewCoordinator.shared.showToast(icon: "lock.fill", title: "Allow", detail: "Screen Recording", tint: .orange)
            return
        }
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ocr-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // Interactive selection, no camera sound; space switches to picking a window
        process.arguments = ["-i", "-x", file.path]
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in continuation.resume() }
                do { try process.run() } catch { continuation.resume(throwing: error) }
            }
        } catch {
            BoringViewCoordinator.shared.showToast(icon: "exclamationmark.triangle.fill", title: "Capture", detail: "failed", tint: .orange)
            return
        }
        // Esc leaves no file
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        await copyText(from: [file])
    }

    /// OCR on files (screenshots, photos, scanned PDFs), copied as one text
    static func copyText(from files: [URL]) async {
        var parts: [String] = []
        for file in files {
            if let text = try? await TextRecognizer.text(inFile: file), !text.isEmpty {
                parts.append(text)
            }
        }
        let text = parts.joined(separator: "\n\n")
        guard !text.isEmpty else {
            BoringViewCoordinator.shared.showToast(icon: "text.viewfinder", title: "No text", detail: "found", tint: .gray)
            return
        }
        // Not marked as our own change: the text belongs in the clipboard history, and English text gets the Translate hint
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let words = TextLayout.wordCount(text)
        BoringViewCoordinator.shared.showToast(icon: "text.viewfinder", title: "Copied", detail: words == 1 ? "1 word" : "\(words) words", tint: .green)
    }
}
