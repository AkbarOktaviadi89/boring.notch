//
//  ShortLinkManager.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import AppKit
import Combine
import CoreImage.CIFilterBuiltins
import Defaults

extension ShortLinkService: Defaults.Serializable {}
extension ShortLinkRecord: Defaults.Serializable {}

/// Shortens links with is.gd or TinyURL, keeps the recent ones, and draws their QR codes
@MainActor
final class ShortLinkManager: ObservableObject {
    static let shared = ShortLinkManager()

    @Published private(set) var history: [ShortLinkRecord] = Defaults[.shortLinkHistory] {
        didSet { Defaults[.shortLinkHistory] = history }
    }
    @Published private(set) var current: ShortLinkRecord?
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?
    /// A link that looks like it carries a secret, waiting for "Shorten anyway"
    @Published private(set) var warning: (url: URL, reason: String)?
    @Published private(set) var didCopy = false
    /// Set when the chosen service refused and the other one made the link
    @Published private(set) var notice: String?

    private var qrCache: [String: NSImage] = [:]
    private var copiedResetTask: Task<Void, Never>?

    private init() {}

    /// Shortens, copies the short link and returns it. Stops at a warning unless `confirmed`.
    @discardableResult
    func shorten(_ text: String, service: ShortLinkService = Defaults[.shortLinkService], confirmed: Bool = false) async -> ShortLinkRecord? {
        errorMessage = nil
        warning = nil
        notice = nil
        guard let url = ShortLinks.normalize(text) else {
            errorMessage = ShortLinkError.notALink.errorDescription
            return nil
        }
        if ShortLinks.isShortened(url) {
            errorMessage = ShortLinkError.alreadyShort.errorDescription
            return nil
        }
        if !confirmed, let reason = ShortLinks.sensitiveReason(url) {
            warning = (url, reason)
            current = nil
            return nil
        }
        // The same link was shortened before: reuse it instead of asking again
        if let known = history.first(where: { $0.original == url.absoluteString && $0.service == service }) {
            finish(known)
            return known
        }

        isWorking = true
        defer { isWorking = false }
        var result = await request(url, service: service)
        // A browser check can't be passed from here; the other service usually works
        if case .failure(.blocked) = result, let other = ShortLinkService.allCases.first(where: { $0 != service }) {
            result = await request(url, service: other)
            if case .success = result {
                notice = "\(service.rawValue) is blocking automatic requests right now, so \(other.rawValue) made this one."
            }
        }
        switch result {
        case .success(let record):
            history = ShortLinks.addingToHistory(record, history)
            finish(record)
            return record
        case .failure(let error):
            errorMessage = error.errorDescription
            current = nil
            return nil
        }
    }

    private func request(_ url: URL, service: ShortLinkService) async -> Result<ShortLinkRecord, ShortLinkError> {
        guard let endpoint = service.requestURL(for: url.absoluteString) else { return .failure(.notALink) }
        do {
            var request = URLRequest(url: endpoint, timeoutInterval: 12)
            request.setValue("BoringNotch", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return ShortLinks.parseResponse(String(decoding: data, as: UTF8.self), statusCode: status).map { short in
                ShortLinkRecord(original: url.absoluteString, short: short.absoluteString, service: service)
            }
        } catch {
            let message = (error as? URLError)?.code == .notConnectedToInternet
                ? "No internet connection."
                : "\(service.rawValue) didn't answer: \(error.localizedDescription)"
            return .failure(.rejected(message))
        }
    }

    private func finish(_ record: ShortLinkRecord) {
        current = record
        copy(record)
    }

    func copy(_ record: ShortLinkRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.short, forType: .string)
        // Our own copy isn't a link to offer back
        ClipboardWatcher.shared.ignoreCurrentChange()
        didCopy = true
        copiedResetTask?.cancel()
        copiedResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.didCopy = false
        }
    }

    func show(_ record: ShortLinkRecord) {
        warning = nil
        errorMessage = nil
        notice = nil
        current = record
    }

    func remove(_ record: ShortLinkRecord) {
        history.removeAll { $0.id == record.id }
        if current?.id == record.id { current = nil }
    }

    func clearHistory() {
        history = []
        current = nil
    }

    func dismissMessages() {
        warning = nil
        errorMessage = nil
        notice = nil
    }

    /// Sharp at any size: one pixel per module, scaled up without smoothing
    func qrCode(for text: String) -> NSImage? {
        if let cached = qrCache[text] { return cached }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cgImage = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: output.extent.width, height: output.extent.height))
        qrCache[text] = image
        return image
    }
}
