//
//  DevToolsManager.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import AppKit
import Combine

@MainActor
final class DevToolsManager: ObservableObject {
    static let shared = DevToolsManager()

    enum Category: String, CaseIterable, Identifiable {
        case dev = "Dev"
        case security = "Security"

        var id: Self { self }

        var tools: [Tool] {
            Tool.allCases.filter { $0.category == self }
        }
    }

    enum Tool: String, CaseIterable, Identifiable {
        case json = "JSON"
        case base64 = "Base64"
        case url = "URL"
        case uuid = "UUID"
        case timestamp = "Time"
        case color = "Color"
        case jwt = "JWT"
        case hash = "Hash"
        case hex = "Hex"
        case html = "HTML"
        case unicode = "Unicode"
        case smart = "Smart"

        var id: Self { self }

        var category: Category {
            switch self {
            case .json, .base64, .url, .uuid, .timestamp, .color: return .dev
            case .jwt, .hash, .hex, .html, .unicode, .smart: return .security
            }
        }

        /// Tools that work on text the user types or pastes
        var takesInput: Bool {
            switch self {
            case .uuid, .color: return false
            default: return true
            }
        }
    }

    @Published var tool: Tool = .json {
        didSet {
            if tool != oldValue { clearOutput() }
        }
    }

    var category: Category {
        get { tool.category }
        set {
            guard newValue != tool.category, let first = newValue.tools.first else { return }
            tool = first
        }
    }
    @Published var input: String = ""
    @Published var uppercaseUUID = false
    @Published private(set) var result: DevToolResult?
    @Published private(set) var errorMessage: String?
    @Published private(set) var didCopy = false

    private var copiedResetTask: Task<Void, Never>?

    private init() {}

    func run(_ transform: (String) throws -> DevToolResult) {
        do {
            show(try transform(input))
        } catch {
            result = nil
            errorMessage = error.localizedDescription
        }
    }

    func show(_ result: DevToolResult) {
        self.result = result
        errorMessage = nil
        didCopy = false
    }

    func clearOutput() {
        result = nil
        errorMessage = nil
        didCopy = false
    }

    func pasteFromClipboard() {
        input = NSPasteboard.general.string(forType: .string) ?? ""
        clearOutput()
    }

    func useCurrentTime() {
        input = String(Int64(Date().timeIntervalSince1970))
        run { try DevTransforms.convertTimestamp($0) }
    }

    func copyResult() {
        guard let primary = result?.primary else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(primary, forType: .string)
        didCopy = true
        copiedResetTask?.cancel()
        copiedResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.didCopy = false
        }
    }

    /// Shows the system magnifier and reports the color under the cursor
    func pickColorFromScreen() {
        NSColorSampler().show { [weak self] color in
            guard let color = color?.usingColorSpace(.sRGB) else { return }
            Task { @MainActor in
                self?.show(DevTransforms.color(
                    red: Double(color.redComponent),
                    green: Double(color.greenComponent),
                    blue: Double(color.blueComponent)
                ))
            }
        }
    }
}
