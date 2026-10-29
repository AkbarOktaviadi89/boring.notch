//
//  TranslateManager.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import AppKit
import Combine
import NaturalLanguage

/// Text for the translate panel and the language pair. The translating itself happens in TranslateView:
/// Apple's Translation framework hands out its session only through a SwiftUI modifier.
@MainActor
final class TranslateManager: ObservableObject {
    static let shared = TranslateManager()

    @Published var input = ""
    @Published var output = ""
    @Published var source = TranslationPlan.foreign
    @Published var target = TranslationPlan.home
    @Published var errorMessage: String?
    @Published var isTranslating = false
    /// Bumped to ask the view to translate the current input
    @Published private(set) var request = 0
    @Published private(set) var didCopy = false

    private var copiedResetTask: Task<Void, Never>?

    private init() {}

    static func detectLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    /// Loads text, picks the direction from its language and asks for a translation
    func load(_ text: String) {
        input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let plan = TranslationPlan.direction(detected: Self.detectLanguage(input))
        source = plan.source
        target = plan.target
        translate()
    }

    func translate() {
        output = ""
        errorMessage = nil
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        request += 1
    }

    func swap() {
        (source, target) = (target, source)
        if !output.isEmpty { input = output }
        translate()
    }

    func loadClipboard() {
        if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
            load(text)
        }
    }

    func copyOutput() {
        guard !output.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        ClipboardWatcher.shared.ignoreCurrentChange()
        didCopy = true
        copiedResetTask?.cancel()
        copiedResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.didCopy = false
        }
    }

    static func name(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }
}
