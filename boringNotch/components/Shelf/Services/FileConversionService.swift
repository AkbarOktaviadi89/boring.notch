//
//  FileConversionService.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-28.
//

import AppKit
import AVFoundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum ConversionError: LocalizedError {
    case unreadable(String)
    case writeFailed(String)
    case noAudio(String)
    case notSmaller(String)
    case needsApp(String, [String])
    case appFailed(String, String)
    case exportFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name):
            return "\(name) couldn't be read."
        case .writeFailed(let name):
            return "\(name) couldn't be saved to Downloads."
        case .noAudio(let name):
            return "\(name) has no sound to extract."
        case .notSmaller(let name):
            return "\(name) is already as small as it gets, so it was left as it is."
        case .needsApp(let name, let apps):
            return "\(name) needs \(apps.joined(separator: " or ")) to be turned into a PDF."
        case .appFailed(let app, let detail):
            return "\(app) couldn't export the PDF: \(detail)\n\nIf macOS asked whether Boring Notch may control \(app), allow it in System Settings › Privacy & Security › Automation."
        case .exportFailed(let name, let detail):
            return "\(name) couldn't be converted: \(detail)"
        }
    }
}

/// Turns Shelf files into other formats. Results go to Downloads, next to where the user looks for them.
@MainActor
final class FileConversionService: ObservableObject {
    static let shared = FileConversionService()

    /// What is running now, for the Shelf: "Converting with Microsoft Word…"
    @Published private(set) var status: String?

    var outputDirectory: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSTemporaryDirectory())

    /// Runs the action on the files it accepts and returns what it made: files, or a folder for split pages
    func run(_ action: ConversionAction, on urls: [URL]) async throws -> [URL] {
        let inputs = urls.filter { action.accepts(Conversions.kind(ofExtension: $0.pathExtension)) }
        guard !inputs.isEmpty else { return [] }
        status = inputs.count == 1 ? "Converting \(inputs[0].lastPathComponent)…" : "Converting \(inputs.count) files…"
        defer { status = nil }

        switch action {
        case .imagesToPDF:
            let output = destination(Conversions.outputName(for: action, input: inputs[0].lastPathComponent))
            try await Task.detached { try Self.imagesToPDF(inputs, output: output) }.value
            return [output]
        case .mergePDFs:
            let output = destination(Conversions.outputName(for: action, input: inputs[0].lastPathComponent))
            try await Task.detached { try Self.mergePDFs(inputs, output: output) }.value
            return [output]
        default:
            var results: [URL] = []
            for input in inputs {
                results.append(try await convert(input, action: action))
            }
            return results
        }
    }

    private func convert(_ input: URL, action: ConversionAction) async throws -> URL {
        let output = destination(Conversions.outputName(for: action, input: input.lastPathComponent))
        switch action {
        case .toJPG, .toPNG, .toHEIC, .toTIFF:
            let ext = action.imageExtension ?? "jpg"
            try await Task.detached { try Self.writeImage(input, to: output, ext: ext, maxPixels: nil, quality: 0.9, keepMetadata: true) }.value
        case .shrinkImage:
            try await Task.detached {
                // Shrunk for sharing, so location and camera details stay behind
                try Self.writeImage(input, to: output, ext: "jpg", maxPixels: Conversions.uploadMaxPixels,
                                    quality: Conversions.uploadQuality, keepMetadata: false)
            }.value
        case .splitPDF:
            return try await Task.detached { try Self.splitPDF(input, into: output) }.value
        case .pdfToImages:
            return try await Task.detached { try Self.pdfToImages(input, into: output) }.value
        case .compressPDF:
            try await Task.detached { try Self.compressPDF(input, to: output) }.value
        case .toMP4:
            // Rewrapping keeps the original quality and takes seconds; re-encoding is only for codecs MP4 can't hold
            let asset = AVURLAsset(url: input)
            let rewrap = await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPresetPassthrough, with: asset, outputFileType: .mp4)
            try await export(input, to: output, preset: rewrap ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality, type: .mp4)
        case .shrinkVideo:
            try await VideoShrinker.shrink(input, to: output)
        case .extractAudio, .audioToM4A:
            try await export(input, to: output, preset: AVAssetExportPresetAppleM4A, type: .m4a)
        case .documentToPDF:
            try await convertDocument(input, to: output)
        case .imagesToPDF, .mergePDFs:
            break
        }
        return output
    }

    /// A free name in the output folder
    private func destination(_ name: String) -> URL {
        let folder = outputDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let unique = Conversions.uniqueName(name) { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
        return folder.appendingPathComponent(unique)
    }

    // MARK: - Images

    /// Upright pixels, so formats without an orientation tag (PNG) still show the photo the right way round
    nonisolated private static func uprightImage(_ source: CGImageSource, maxPixels: Int?) -> CGImage? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let longest = max(width, height)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixels ?? longest, max(longest, 1)),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// JPEG has no transparency; without a white backdrop see-through parts would turn black
    nonisolated private static func flattened(_ image: CGImage) -> CGImage {
        guard image.alphaInfo != .none, image.alphaInfo != .noneSkipLast, image.alphaInfo != .noneSkipFirst,
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(.white)
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage() ?? image
    }

    nonisolated static func writeImage(_ input: URL, to output: URL, ext: String, maxPixels: Int?, quality: Double, keepMetadata: Bool) throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              var image = uprightImage(source, maxPixels: maxPixels) else {
            throw ConversionError.unreadable(input.lastPathComponent)
        }
        let type = UTType(filenameExtension: ext) ?? .jpeg
        if type == .jpeg { image = flattened(image) }
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConversionError.writeFailed(output.lastPathComponent)
        }
        var properties: [CFString: Any] = [:]
        if keepMetadata, let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            properties = original
            // The pixels are already upright
            properties[kCGImagePropertyOrientation] = 1
            if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                tiff[kCGImagePropertyTIFFOrientation] = 1
                properties[kCGImagePropertyTIFFDictionary] = tiff
            }
        }
        properties[kCGImageDestinationLossyCompressionQuality] = quality
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.writeFailed(output.lastPathComponent)
        }
    }

    /// One A4 page per image, turned to landscape for wide images. Photos are re-encoded as JPEG so the PDF stays small.
    nonisolated static func imagesToPDF(_ inputs: [URL], output: URL) throws {
        let portrait = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 24
        guard let context = CGContext(output as CFURL, mediaBox: nil, nil) else {
            throw ConversionError.writeFailed(output.lastPathComponent)
        }
        var pages = 0
        for input in inputs {
            guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
                  let upright = uprightImage(source, maxPixels: 2400),
                  let image = jpegBacked(flattened(upright)) else { continue }
            var box = image.width > image.height ? CGRect(x: 0, y: 0, width: portrait.height, height: portrait.width) : portrait
            context.beginPage(mediaBox: &box)
            let area = box.insetBy(dx: margin, dy: margin)
            let scale = min(area.width / CGFloat(image.width), area.height / CGFloat(image.height))
            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            context.draw(image, in: CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height))
            context.endPage()
            pages += 1
        }
        context.closePDF()
        guard pages > 0 else {
            try? FileManager.default.removeItem(at: output)
            throw ConversionError.unreadable(inputs.map(\.lastPathComponent).joined(separator: ", "))
        }
    }

    /// Quartz copies a JPEG-backed image into the PDF as-is instead of storing raw pixels
    nonisolated private static func jpegBacked(_ image: CGImage) -> CGImage? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination),
              let source = CGImageSourceCreateWithData(data, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - PDF

    nonisolated private static func document(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else { throw ConversionError.unreadable(url.lastPathComponent) }
        return document
    }

    nonisolated private static func write(_ document: PDFDocument, to url: URL, options: [PDFDocumentWriteOption: Any] = [:]) throws {
        guard document.write(to: url, withOptions: options) else { throw ConversionError.writeFailed(url.lastPathComponent) }
    }

    nonisolated static func mergePDFs(_ inputs: [URL], output: URL) throws {
        let merged = PDFDocument()
        for input in inputs {
            let source = try document(input)
            for index in 0..<source.pageCount {
                guard let page = source.page(at: index)?.copy() as? PDFPage else { continue }
                merged.insert(page, at: merged.pageCount)
            }
        }
        try write(merged, to: output)
    }

    /// Each page as its own PDF, in a folder named after the file
    nonisolated static func splitPDF(_ input: URL, into folder: URL) throws -> URL {
        let source = try document(input)
        let base = input.deletingPathExtension().lastPathComponent
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 0..<source.pageCount {
            guard let page = source.page(at: index)?.copy() as? PDFPage else { continue }
            let single = PDFDocument()
            single.insert(page, at: 0)
            try write(single, to: folder.appendingPathComponent(
                Conversions.pageName(base: base, page: index + 1, of: source.pageCount, ext: "pdf")))
        }
        return folder
    }

    /// PNG per page at twice the PDF's size, sharp enough for slides and screenshots.
    /// A one-page PDF gives a single image instead of a folder.
    nonisolated static func pdfToImages(_ input: URL, into folder: URL) throws -> URL {
        let source = try document(input)
        let base = input.deletingPathExtension().lastPathComponent
        guard source.pageCount > 0 else { throw ConversionError.unreadable(input.lastPathComponent) }
        let single = source.pageCount == 1
        if !single { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }

        var firstImage: URL?
        for index in 0..<source.pageCount {
            guard let page = source.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let turned = page.rotation % 180 != 0
            let size = NSSize(width: (turned ? bounds.height : bounds.width) * 2, height: (turned ? bounds.width : bounds.height) * 2)
            let thumbnail = page.thumbnail(of: size, for: .mediaBox)
            guard let image = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let url = single
                ? folder.deletingLastPathComponent().appendingPathComponent(
                    Conversions.uniqueName("\(base).png") { FileManager.default.fileExists(atPath: folder.deletingLastPathComponent().appendingPathComponent($0).path) })
                : folder.appendingPathComponent(Conversions.pageName(base: base, page: index + 1, of: source.pageCount, ext: "png"))
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, flattened(image), nil)
            if CGImageDestinationFinalize(destination), firstImage == nil { firstImage = url }
        }
        guard let firstImage else { throw ConversionError.writeFailed(input.lastPathComponent) }
        return single ? firstImage : folder
    }

    /// Re-saves images inside the PDF as screen-resolution JPEGs. Text and vector pages barely change.
    nonisolated static func compressPDF(_ input: URL, to output: URL) throws {
        let source = try document(input)
        try write(source, to: output, options: [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true])
        let before = (try? input.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let after = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        // Only worth keeping when it actually saved space
        if after == 0 || Double(after) > Double(before) * 0.95 {
            try? FileManager.default.removeItem(at: output)
            throw ConversionError.notSmaller(input.lastPathComponent)
        }
    }

    // MARK: - Video and audio

    private func export(_ input: URL, to output: URL, preset: String, type: AVFileType) async throws {
        let asset = AVURLAsset(url: input)
        if type == .m4a, (try? await asset.loadTracks(withMediaType: .audio))?.isEmpty ?? true {
            throw ConversionError.noAudio(input.lastPathComponent)
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ConversionError.unreadable(input.lastPathComponent)
        }
        session.outputURL = output
        session.outputFileType = type
        session.shouldOptimizeForNetworkUse = true
        await session.export()
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            throw ConversionError.exportFailed(input.lastPathComponent, session.error?.localizedDescription ?? "unknown error")
        }
    }

    // MARK: - Documents

    /// Microsoft Office or Apple's apps when installed, for a PDF that looks exactly like the document;
    /// macOS's own text layout otherwise, which handles text and simple formatting
    private func convertDocument(_ input: URL, to output: URL) async throws {
        let ext = input.pathExtension
        let candidates = Conversions.documentApps(forExtension: ext)
        let installed = candidates.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.rawValue) != nil }

        var failures: [String] = []
        for app in installed {
            status = "Converting with \(app.name)…"
            do {
                try await convertWithApp(app, input: input, output: output)
                return
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        if Conversions.canConvertNatively(extension: ext) {
            status = "Converting \(input.lastPathComponent)…"
            try Self.convertNatively(input, to: output)
            return
        }
        guard !failures.isEmpty else { throw ConversionError.needsApp(input.lastPathComponent, candidates.map(\.name)) }
        // Every app that was tried, not just the last one
        throw ConversionError.exportFailed(input.lastPathComponent, "\n\n" + failures.joined(separator: "\n\n"))
    }

    /// The app's own sandbox can't reach the user's file, so the file is handed over in a folder the app shares with others
    private func convertWithApp(_ app: DocumentApp, input: URL, output: URL) async throws {
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { throw ConversionError.appFailed(app.name, "no home folder") }
        let workFolder = URL(fileURLWithPath: String(cString: home))
            .appendingPathComponent(app.sharedFolder)
            .appendingPathComponent("Boring Notch")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workFolder) }

        let handedIn = workFolder.appendingPathComponent(input.lastPathComponent)
        let handedOut = workFolder.appendingPathComponent(input.deletingPathExtension().lastPathComponent + ".pdf")
        try FileManager.default.copyItem(at: input, to: handedIn)

        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: app.rawValue).isEmpty
        do {
            try await AppleScriptHelper.executeVoid(Conversions.exportScript(app: app, input: handedIn.path, output: handedOut.path))
        } catch {
            try? await AppleScriptHelper.executeVoid(Conversions.closeScript(app: app, quit: !wasRunning))
            let message = (error as NSError).userInfo[NSAppleScript.errorMessage] as? String ?? error.localizedDescription
            throw ConversionError.appFailed(app.name, message)
        }
        // PowerPoint in particular finishes writing after the save command returns: wait for the file to settle
        let pdf = await Self.waitForFinishedFile(in: workFolder, expected: handedOut, timeout: .seconds(90))
        try? await AppleScriptHelper.executeVoid(Conversions.closeScript(app: app, quit: !wasRunning))
        guard let pdf else {
            let found = (try? FileManager.default.contentsOfDirectory(atPath: workFolder.path)) ?? []
            throw ConversionError.appFailed(app.name, "no PDF came out (folder had: \(found.joined(separator: ", ")))")
        }
        try FileManager.default.moveItem(at: pdf, to: output)
    }

    /// The expected PDF, or any PDF the app wrote under another name, once its size stops changing
    private static func waitForFinishedFile(in folder: URL, expected: URL, timeout: Duration) async -> URL? {
        let deadline = ContinuousClock.now + timeout
        var lastSize = -1
        while ContinuousClock.now < deadline {
            let candidate = FileManager.default.fileExists(atPath: expected.path)
                ? expected
                : ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                    .first { $0.pathExtension.lowercased() == "pdf" }
            if let candidate {
                let size = (try? candidate.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size > 0 && size == lastSize { return candidate }
                lastSize = size
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }

    /// Lays the text out on A4 pages and prints them to a PDF without showing a print dialog
    static func convertNatively(_ input: URL, to output: URL) throws {
        let ext = input.pathExtension.lowercased()
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
        if ext == "md" || ext == "txt" {
            options[.documentType] = NSAttributedString.DocumentType.plain
            options[.characterEncoding] = String.Encoding.utf8.rawValue
        }
        let text: NSAttributedString
        do {
            text = try NSAttributedString(url: input, options: options, documentAttributes: nil)
        } catch {
            throw ConversionError.unreadable(input.lastPathComponent)
        }

        let paper = NSSize(width: 595, height: 842)
        let margin: CGFloat = 56
        let info = NSPrintInfo()
        info.paperSize = paper
        info.topMargin = margin
        info.bottomMargin = margin
        info.leftMargin = margin
        info.rightMargin = margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = output

        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: paper.width - 2 * margin, height: 1))
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        view.backgroundColor = .white
        view.textStorage?.setAttributedString(text)
        view.sizeToFit()

        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run(), FileManager.default.fileExists(atPath: output.path) else {
            throw ConversionError.writeFailed(output.lastPathComponent)
        }
    }
}

/// Re-encodes a video as H.264 at most 720p with a bitrate to match, plus AAC sound.
/// The export presets keep a high bitrate, so a screen recording could come out bigger than it went in.
enum VideoShrinker {
    static let maxLongSide: CGFloat = 1280
    /// For a 1280x720 picture; smaller pictures get proportionally less
    static let bitrateAt720p = 2_500_000.0

    /// Wraps reader and writer objects for the encoding queues, which only touch them one at a time
    private final class Box<T>: @unchecked Sendable {
        let value: T
        init(_ value: T) { self.value = value }
    }

    static func shrink(_ input: URL, to output: URL) async throws {
        let name = input.lastPathComponent
        let asset = AVURLAsset(url: input)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw ConversionError.unreadable(name)
        }
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let (naturalSize, transform) = try await video.load(.naturalSize, .preferredTransform)

        // Encoded in the track's own orientation; the transform turns it upright on playback
        let longSide = max(naturalSize.width, naturalSize.height)
        let scale = min(1, maxLongSide / max(longSide, 1))
        let width = Int((naturalSize.width * scale / 2).rounded()) * 2
        let height = Int((naturalSize.height * scale / 2).rounded()) * 2
        let bitrate = max(800_000, bitrateAt720p * Double(width * height) / (1280 * 720))

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        let videoOut = AVAssetReaderTrackOutput(track: video, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        videoOut.alwaysCopiesSampleData = false
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        videoIn.transform = transform
        videoIn.expectsMediaDataInRealTime = false
        guard reader.canAdd(videoOut), writer.canAdd(videoIn) else { throw ConversionError.unreadable(name) }
        reader.add(videoOut)
        writer.add(videoIn)

        var pairs = [(Box(videoOut), Box(videoIn))]
        if let audio {
            let audioOut = AVAssetReaderTrackOutput(track: audio, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000,
            ])
            audioIn.expectsMediaDataInRealTime = false
            if reader.canAdd(audioOut), writer.canAdd(audioIn) {
                reader.add(audioOut)
                writer.add(audioIn)
                pairs.append((Box(audioOut), Box(audioIn)))
            }
        }

        guard reader.startReading(), writer.startWriting() else {
            throw ConversionError.exportFailed(name, (writer.error ?? reader.error)?.localizedDescription ?? "couldn't start")
        }
        writer.startSession(atSourceTime: .zero)

        let readerBox = Box(reader)
        await withTaskGroup(of: Void.self) { group in
            for (index, (out, into)) in pairs.enumerated() {
                group.addTask {
                    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                        let queue = DispatchQueue(label: "BoringNotch.VideoShrinker.\(index)")
                        into.value.requestMediaDataWhenReady(on: queue) {
                            while into.value.isReadyForMoreMediaData {
                                if readerBox.value.status == .reading, let buffer = out.value.copyNextSampleBuffer() {
                                    if !into.value.append(buffer) { break }
                                } else {
                                    into.value.markAsFinished()
                                    done.resume()
                                    return
                                }
                            }
                        }
                    }
                }
            }
        }

        if reader.status == .failed || writer.status == .failed {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: output)
            throw ConversionError.exportFailed(name, (writer.error ?? reader.error)?.localizedDescription ?? "unknown error")
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            throw ConversionError.exportFailed(name, writer.error?.localizedDescription ?? "unknown error")
        }

        let before = (try? input.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let after = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if before > 0, after >= before {
            try? FileManager.default.removeItem(at: output)
            throw ConversionError.notSmaller(name)
        }
    }
}
