//
//  Conversions.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-28.
//

import Foundation

/// What a Shelf file is, as far as converting it goes
enum ConvertibleKind: Equatable {
    case image
    case pdf
    case video
    case audio
    case document(DocumentFamily)
}

enum DocumentFamily: Equatable {
    /// Word documents, RTF, plain text and HTML
    case text
    case spreadsheet
    case presentation
    case pages
    case numbers
    case keynote
}

/// Apps that can turn a document into a PDF exactly as it looks, driven with AppleScript
enum DocumentApp: String, CaseIterable {
    case word = "com.microsoft.Word"
    case excel = "com.microsoft.Excel"
    case powerPoint = "com.microsoft.Powerpoint"
    case pages = "com.apple.iWork.Pages"
    case numbers = "com.apple.iWork.Numbers"
    case keynote = "com.apple.iWork.Keynote"

    var name: String {
        switch self {
        case .word: return "Microsoft Word"
        case .excel: return "Microsoft Excel"
        case .powerPoint: return "Microsoft PowerPoint"
        case .pages: return "Pages"
        case .numbers: return "Numbers"
        case .keynote: return "Keynote"
        }
    }

    /// A group container the app can read and write without asking, so files are handed over there
    var sharedFolder: String {
        switch self {
        case .word, .excel, .powerPoint: return "Library/Group Containers/UBF8T346G9.Office"
        case .pages, .numbers, .keynote: return "Library/Group Containers/74J34U3R6X.com.apple.iWork"
        }
    }
}

/// In menu order
enum ConversionAction: String, CaseIterable {
    case documentToPDF
    case toJPG, toPNG, toHEIC, toTIFF, shrinkImage, imagesToPDF
    case mergePDFs, splitPDF, pdfToImages, compressPDF
    case toMP4, extractAudio, shrinkVideo, audioToM4A

    var title: String {
        switch self {
        case .toJPG: return "Image to JPG"
        case .toPNG: return "Image to PNG"
        case .toHEIC: return "Image to HEIC"
        case .toTIFF: return "Image to TIFF"
        case .shrinkImage: return "Shrink Image for Upload"
        case .imagesToPDF: return "Images to One PDF"
        case .mergePDFs: return "Merge PDFs"
        case .splitPDF: return "Split PDF into Pages"
        case .pdfToImages: return "PDF Pages to Images"
        case .compressPDF: return "Compress PDF"
        case .toMP4: return "Video to MP4"
        case .extractAudio: return "Video to Audio (M4A)"
        case .shrinkVideo: return "Shrink Video (720p)"
        case .audioToM4A: return "Audio to M4A"
        case .documentToPDF: return "Document to PDF"
        }
    }

    /// Actions of one group sit together in the menu, between separators
    var group: Int {
        switch self {
        case .documentToPDF: return 0
        case .toJPG, .toPNG, .toHEIC, .toTIFF, .shrinkImage, .imagesToPDF: return 1
        case .mergePDFs, .splitPDF, .pdfToImages, .compressPDF: return 2
        case .toMP4, .extractAudio, .shrinkVideo, .audioToM4A: return 3
        }
    }

    /// The kind of file the action takes
    func accepts(_ kind: ConvertibleKind?) -> Bool {
        switch (group, kind) {
        case (0, .document?): return true
        case (1, .image?): return true
        case (2, .pdf?): return true
        case (3, .video?): return self != .audioToM4A
        case (3, .audio?): return self == .audioToM4A
        default: return false
        }
    }

    /// The image format the action writes, or nil when it isn't a format change
    var imageExtension: String? {
        switch self {
        case .toJPG, .shrinkImage: return "jpg"
        case .toPNG: return "png"
        case .toHEIC: return "heic"
        case .toTIFF: return "tiff"
        default: return nil
        }
    }
}

/// Which conversions apply to which files, and what the results are called.
/// Foundation only, so it can be tested without the app.
enum Conversions {
    /// The longest side of an image shrunk for upload, and its JPEG quality
    static let uploadMaxPixels = 2048
    static let uploadQuality = 0.8

    private static let images: Set<String> = ["heic", "heif", "jpg", "jpeg", "png", "tif", "tiff", "gif", "bmp", "webp"]
    private static let videos: Set<String> = ["mov", "mp4", "m4v", "3gp"]
    private static let audios: Set<String> = ["m4a", "mp3", "wav", "aif", "aiff", "caf", "aac", "flac"]
    private static let documents: [String: DocumentFamily] = [
        "doc": .text, "docx": .text, "dotx": .text, "odt": .text, "rtf": .text, "txt": .text,
        "md": .text, "html": .text, "htm": .text,
        "xls": .spreadsheet, "xlsx": .spreadsheet, "csv": .spreadsheet, "ods": .spreadsheet,
        "ppt": .presentation, "pptx": .presentation, "odp": .presentation,
        "pages": .pages, "numbers": .numbers, "key": .keynote,
    ]
    /// Formats macOS can lay out into a PDF itself, without an office app
    private static let nativeDocuments: Set<String> = ["doc", "docx", "dotx", "odt", "rtf", "txt", "md", "html", "htm"]

    static func kind(ofExtension ext: String) -> ConvertibleKind? {
        let ext = ext.lowercased()
        if images.contains(ext) { return .image }
        if ext == "pdf" { return .pdf }
        if videos.contains(ext) { return .video }
        if audios.contains(ext) { return .audio }
        return documents[ext].map(ConvertibleKind.document)
    }

    /// Actions for a selection, in menu order. Each one only touches the files it accepts.
    static func actions(forExtensions extensions: [String]) -> [ConversionAction] {
        let exts = extensions.map { $0.lowercased() }
        let kinds = exts.map(kind(ofExtension:))
        let imageExts = Set(zip(exts, kinds).filter { $0.1 == .image }.map { normalizedImageExtension($0.0) })
        let pdfCount = kinds.filter { $0 == .pdf }.count

        return ConversionAction.allCases.filter { action in
            guard kinds.contains(where: action.accepts) else { return false }
            switch action {
            case .toJPG, .toPNG, .toHEIC, .toTIFF:
                // Offered unless every image is already in that format
                return imageExts != [action.imageExtension]
            case .mergePDFs:
                return pdfCount >= 2
            case .toMP4:
                return zip(exts, kinds).contains { $0.1 == .video && $0.0 != "mp4" }
            case .audioToM4A:
                return zip(exts, kinds).contains { $0.1 == .audio && $0.0 != "m4a" }
            default:
                return true
            }
        }
    }

    private static func normalizedImageExtension(_ ext: String) -> String {
        switch ext {
        case "jpeg": return "jpg"
        case "tif": return "tiff"
        case "heif": return "heic"
        default: return ext
        }
    }

    // MARK: - Names

    /// The result's file name for one input, before making it unique
    static func outputName(for action: ConversionAction, input: String) -> String {
        let base = (input as NSString).deletingPathExtension
        switch action {
        case .shrinkImage: return "\(base) (small).jpg"
        case .toJPG, .toPNG, .toHEIC, .toTIFF: return "\(base).\(action.imageExtension ?? "")"
        case .imagesToPDF, .documentToPDF: return "\(base).pdf"
        case .mergePDFs: return "\(base) (merged).pdf"
        case .compressPDF: return "\(base) (compressed).pdf"
        case .splitPDF: return "\(base) pages"
        case .pdfToImages: return "\(base) images"
        case .toMP4: return "\(base).mp4"
        case .shrinkVideo: return "\(base) (720p).mp4"
        case .extractAudio, .audioToM4A: return "\(base).m4a"
        }
    }

    /// "Report - page 03.pdf": padded so the pages sort in order in Finder
    static func pageName(base: String, page: Int, of count: Int, ext: String) -> String {
        let width = String(max(count, 1)).count
        let number = String(repeating: "0", count: max(0, width - String(page).count)) + String(page)
        return "\(base) - page \(number).\(ext)"
    }

    /// "photo.jpg", then "photo 2.jpg", "photo 3.jpg" while a name is taken, like Finder does
    static func uniqueName(_ name: String, isTaken: (String) -> Bool) -> String {
        guard isTaken(name) else { return name }
        let ns = name as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        var number = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            if !isTaken(candidate) { return candidate }
            number += 1
        }
    }

    // MARK: - Documents

    /// Apps that convert this document, best first: Microsoft Office, then Apple's own apps
    static func documentApps(forExtension ext: String) -> [DocumentApp] {
        guard case .document(let family)? = kind(ofExtension: ext) else { return [] }
        switch family {
        case .text: return [.word, .pages]
        case .spreadsheet: return [.excel, .numbers]
        case .presentation: return [.powerPoint, .keynote]
        case .pages: return [.pages]
        case .numbers: return [.numbers]
        case .keynote: return [.keynote]
        }
    }

    static func canConvertNatively(extension ext: String) -> Bool {
        nativeDocuments.contains(ext.lowercased())
    }

    /// Opens `input` in the app and saves it as a PDF at `output`. Paths are POSIX; Office wants old-style
    /// HFS paths, so the script converts them. PowerPoint may still be writing the PDF when the command
    /// returns, so the document is closed separately, once the PDF is there (`closeScript`).
    static func exportScript(app: DocumentApp, input: String, output: String) -> String {
        let inFile = "POSIX file \(quoted(input))"
        let outPath = "(POSIX file \(quoted(output))) as string"
        let body: String
        switch app {
        case .word:
            body = """
                    open \(inFile)
                    save as active document file name \(outPath) file format format PDF
            """
        case .excel:
            body = """
                    open \(inFile)
                    save workbook as active workbook filename \(outPath) file format PDF file format
            """
        case .powerPoint:
            body = """
                    open \(inFile)
                    save active presentation in \(outPath) as save as PDF
            """
        case .pages, .numbers, .keynote:
            body = """
                    set theDoc to open \(inFile)
                    export theDoc to POSIX file \(quoted(output)) as PDF
            """
        }
        return """
        with timeout of 300 seconds
            tell application id "\(app.rawValue)"
        \(body)
            end tell
        end timeout
        """
    }

    /// Closes the document the export opened without saving it, and quits the app when the export launched it
    static func closeScript(app: DocumentApp, quit: Bool) -> String {
        let close: String
        switch app {
        case .word: close = "close active document saving no"
        case .excel: close = "close active workbook saving no"
        case .powerPoint: close = "close active presentation"
        case .pages, .numbers, .keynote: close = "close front document saving no"
        }
        return """
        tell application id "\(app.rawValue)"
            try
                \(close)
            end try
            \(quit ? "quit" : "")
        end tell
        """
    }

    /// An AppleScript string literal
    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
