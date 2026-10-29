//
//  DownloadNaming.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-30.
//

import Foundation

/// Names of files still downloading, and what they're called once done. Foundation only, so it can be tested without the app.
enum DownloadNaming {
    /// Chrome and the browsers built on it, Safari, Firefox
    private static let partialExtensions = ["crdownload", "download", "part"]

    static func isPartial(_ name: String) -> Bool {
        partialExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// "report.pdf.crdownload" -> "report.pdf". Nil when the browser hasn't picked the real name yet ("Unconfirmed 123.crdownload").
    static func finalName(_ name: String) -> String? {
        guard isPartial(name) else { return name }
        let base = (name as NSString).deletingPathExtension
        if base.hasPrefix("Unconfirmed ") || base.isEmpty { return nil }
        return base
    }

    /// "42%", or "Done" at the end
    static func percent(_ fraction: Double) -> String {
        fraction >= 1 ? "Done" : "\(Int((min(max(fraction, 0), 1) * 100).rounded(.down)))%"
    }

    /// Several downloads at once count as one: the average of their progress
    static func overall(_ fractions: [Double]) -> Double {
        guard !fractions.isEmpty else { return 0 }
        return fractions.map { min(max($0, 0), 1) }.reduce(0, +) / Double(fractions.count)
    }
}
