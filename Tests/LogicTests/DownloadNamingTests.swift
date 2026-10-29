//
//  DownloadNamingTests.swift
//  boringNotch logic tests
//
//  Created by Akbar Oktaviadi on 2026-10-30.
//

import Foundation

func runDownloadNamingTests() {
    check("partial chrome", String(DownloadNaming.isPartial("a.zip.crdownload")), "true")
    check("partial safari", String(DownloadNaming.isPartial("Slides.pdf.download")), "true")
    check("partial firefox", String(DownloadNaming.isPartial("x.dmg.part")), "true")
    check("not partial", String(DownloadNaming.isPartial("x.pdf")), "false")
    check("final chrome", DownloadNaming.finalName("Laporan Akhir.pdf.crdownload") ?? "nil", "Laporan Akhir.pdf")
    check("final safari", DownloadNaming.finalName("Slides.key.download") ?? "nil", "Slides.key")
    check("final firefox", DownloadNaming.finalName("setup.dmg.part") ?? "nil", "setup.dmg")
    check("final unconfirmed", DownloadNaming.finalName("Unconfirmed 512345.crdownload") ?? "nil", "nil")
    check("final already done", DownloadNaming.finalName("photo.png") ?? "nil", "photo.png")
    check("percent", DownloadNaming.percent(0.426), "42%")
    check("percent done", DownloadNaming.percent(1), "Done")
    check("percent clamps", DownloadNaming.percent(-0.5), "0%")
    check("overall", String(format: "%.2f", DownloadNaming.overall([0.2, 0.6, 1.0])), "0.60")
    check("overall empty", String(DownloadNaming.overall([])), "0.0")
}
