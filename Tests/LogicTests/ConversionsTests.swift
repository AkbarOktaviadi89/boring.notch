//
//  ConversionsTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-28.
//

import Foundation

func runConversionsTests() {
    func actions(_ exts: String) -> String {
        Conversions.actions(forExtensions: exts.split(separator: ",").map(String.init)).map(\.rawValue).joined(separator: ",")
    }

    // Kinds
    check("kind heic", String(describing: Conversions.kind(ofExtension: "HEIC")), String(describing: Optional(ConvertibleKind.image)))
    check("kind pdf", String(describing: Conversions.kind(ofExtension: "pdf")), String(describing: Optional(ConvertibleKind.pdf)))
    check("kind docx", String(describing: Conversions.kind(ofExtension: "docx")), String(describing: Optional(ConvertibleKind.document(.text))))
    check("kind key", String(describing: Conversions.kind(ofExtension: "key")), String(describing: Optional(ConvertibleKind.document(.keynote))))
    check("kind zip", String(describing: Conversions.kind(ofExtension: "zip")), "nil")

    // Which actions
    check("actions heic photo", actions("heic"), "toJPG,toPNG,toTIFF,shrinkImage,imagesToPDF")
    check("actions jpeg counts as jpg", actions("jpeg"), "toPNG,toHEIC,toTIFF,shrinkImage,imagesToPDF")
    check("actions mixed images", actions("jpg,png"), "toJPG,toPNG,toHEIC,toTIFF,shrinkImage,imagesToPDF")
    check("actions one pdf", actions("pdf"), "splitPDF,pdfToImages,compressPDF")
    check("actions two pdfs", actions("pdf,PDF"), "mergePDFs,splitPDF,pdfToImages,compressPDF")
    check("actions mov", actions("mov"), "toMP4,extractAudio,shrinkVideo")
    check("actions mp4", actions("mp4"), "extractAudio,shrinkVideo")
    check("actions mp3", actions("mp3"), "audioToM4A")
    check("actions m4a", actions("m4a"), "")
    check("actions docx", actions("docx"), "documentToPDF")
    check("actions mixed selection", actions("docx,pdf,png"), "documentToPDF,toJPG,toHEIC,toTIFF,shrinkImage,imagesToPDF,splitPDF,pdfToImages,compressPDF")
    check("actions unknown", actions("zip,dmg"), "")
    check("accepts audio only for m4a", String(ConversionAction.extractAudio.accepts(.audio)), "false")

    // Names
    check("name to jpg", Conversions.outputName(for: .toJPG, input: "IMG_0042.HEIC"), "IMG_0042.jpg")
    check("name shrink", Conversions.outputName(for: .shrinkImage, input: "photo.png"), "photo (small).jpg")
    check("name doc pdf", Conversions.outputName(for: .documentToPDF, input: "Laporan Akhir.docx"), "Laporan Akhir.pdf")
    check("name merge", Conversions.outputName(for: .mergePDFs, input: "Bab 1.pdf"), "Bab 1 (merged).pdf")
    check("name split folder", Conversions.outputName(for: .splitPDF, input: "Slides.pdf"), "Slides pages")
    check("name audio", Conversions.outputName(for: .extractAudio, input: "Rekaman.mov"), "Rekaman.m4a")
    check("name dotted base", Conversions.outputName(for: .toMP4, input: "v1.2 demo.mov"), "v1.2 demo.mp4")
    check("page name padded", Conversions.pageName(base: "Slides", page: 3, of: 12, ext: "png"), "Slides - page 03.png")
    check("page name single digit", Conversions.pageName(base: "A", page: 3, of: 9, ext: "pdf"), "A - page 3.pdf")
    check("page name hundreds", Conversions.pageName(base: "A", page: 7, of: 120, ext: "pdf"), "A - page 007.pdf")

    let taken: Set<String> = ["photo.jpg", "photo 2.jpg", "pages"]
    check("unique free", Conversions.uniqueName("other.jpg") { taken.contains($0) }, "other.jpg")
    check("unique numbered", Conversions.uniqueName("photo.jpg") { taken.contains($0) }, "photo 3.jpg")
    check("unique folder", Conversions.uniqueName("pages") { taken.contains($0) }, "pages 2")

    // Documents
    check("apps for docx", Conversions.documentApps(forExtension: "docx").map(\.name).joined(separator: ","), "Microsoft Word,Pages")
    check("apps for xlsx", Conversions.documentApps(forExtension: "XLSX").map(\.name).joined(separator: ","), "Microsoft Excel,Numbers")
    check("apps for pptx", Conversions.documentApps(forExtension: "pptx").map(\.name).joined(separator: ","), "Microsoft PowerPoint,Keynote")
    check("apps for pages", Conversions.documentApps(forExtension: "pages").map(\.name).joined(separator: ","), "Pages")
    check("apps for png", Conversions.documentApps(forExtension: "png").map(\.name).joined(separator: ","), "")
    check("native docx", String(Conversions.canConvertNatively(extension: "DOCX")), "true")
    check("native xlsx", String(Conversions.canConvertNatively(extension: "xlsx")), "false")

    check("quoted plain", Conversions.quoted("/a/b.docx"), "\"/a/b.docx\"")
    check("quoted escapes", Conversions.quoted("/a/\"x\" \\y.docx"), "\"/a/\\\"x\\\" \\\\y.docx\"")
    let word = Conversions.exportScript(app: .word, input: "/in/a.docx", output: "/out/a.pdf")
    contains("script word app", word, "tell application id \"com.microsoft.Word\"")
    contains("script sets input", word, "set inFile to POSIX file \"/in/a.docx\"")
    contains("script sets output path", word, "set outPath to outFile as string")
    contains("script word saves pdf", word, "save as active document file name outPath file format format PDF")
    check("script export leaves the document open", String(word.contains("close")), "false")
    contains("script pages exports", Conversions.exportScript(app: .pages, input: "/in/a.pages", output: "/out/a.pdf"),
             "export theDoc to outFile as PDF")
    contains("script excel", Conversions.exportScript(app: .excel, input: "/i.xlsx", output: "/o.pdf"), "file format PDF file format")
    let powerPoint = Conversions.exportScript(app: .powerPoint, input: "/i.pptx", output: "/o.pdf")
    contains("script powerpoint", powerPoint, "save active presentation in outPath as save as PDF")
    // "as string" inside the save command made PowerPoint see its "as" parameter twice
    check("script powerpoint one as", String(powerPoint.components(separatedBy: "save active presentation")[1].components(separatedBy: "\n")[0].contains("as string")), "false")
    contains("close powerpoint", Conversions.closeScript(app: .powerPoint, quit: false), "close active presentation")
    check("close keeps running app", String(Conversions.closeScript(app: .word, quit: false).contains("quit")), "false")
    contains("close quits launched app", Conversions.closeScript(app: .keynote, quit: true), "quit")

    // Drop tiles while dragging
    func quick(_ kinds: [ConvertibleKind], _ count: Int = 1) -> String {
        Conversions.quickActions(for: kinds, fileCount: count).map(\.rawValue).joined(separator: ",")
    }
    check("quick image", quick([.image]), "imagesToPDF,toJPG,shrinkImage,toPNG")
    check("quick one pdf", quick([.pdf]), "compressPDF,pdfToImages,splitPDF")
    check("quick two pdfs", quick([.pdf], 2), "mergePDFs,compressPDF,pdfToImages")
    check("quick document", quick([.document(.text)]), "documentToPDF")
    check("quick video", quick([.video]), "toMP4,extractAudio,shrinkVideo")
    check("quick mixed keeps one each", quick([.image, .pdf]), "imagesToPDF,compressPDF,pdfToImages,splitPDF")
    check("quick nothing", quick([]), "")
    check("short title", ConversionAction.documentToPDF.shortTitle, "To PDF")
}
