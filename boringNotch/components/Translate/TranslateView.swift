//
//  TranslateView.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import SwiftUI
import Translation

/// Indonesian ↔ English with Apple's on-device translator. Opened from the "Translate" clipboard hint or ⌃⌥⌘L.
struct TranslateView: View {
    var body: some View {
        if #available(macOS 15.0, *) {
            TranslatePanel()
        } else {
            Text("Translating needs macOS 15 or later.")
                .font(.callout)
                .foregroundStyle(.gray)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@available(macOS 15.0, *)
private struct TranslatePanel: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var translator = TranslateManager.shared
    @State private var configuration: TranslationSession.Configuration?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(TranslateManager.name(translator.source))
                    .font(.caption.weight(.semibold))
                Button(action: translator.swap) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 18)
                        .background(Capsule().fill(Color(nsColor: .secondarySystemFill)))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Swap languages")
                Text(TranslateManager.name(translator.target))
                    .font(.caption.weight(.semibold))
                Spacer()
                pill("Paste", icon: "doc.on.clipboard") { translator.loadClipboard() }
                pill("Translate", icon: "character.bubble", primary: true) { translator.translate() }
            }
            .foregroundStyle(.white)

            HStack(alignment: .top, spacing: 8) {
                TextField("Type or paste text", text: $translator.input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .lineLimit(2...5)
                    .focused($inputFocused)
                    .onSubmit { translator.translate() }
                    .onExitCommand(perform: close)
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .secondarySystemFill)))

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05))
                    if translator.isTranslating {
                        ProgressView().controlSize(.small).padding(8)
                    } else if let error = translator.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(4)
                            .padding(8)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            Text(translator.output.isEmpty ? "Translation appears here" : translator.output)
                                .font(.callout)
                                .foregroundStyle(translator.output.isEmpty ? .gray : .white)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .allowsScrollingInOpenNotch()
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !translator.output.isEmpty {
                        pill(translator.didCopy ? "Copied" : "Copy", icon: translator.didCopy ? "checkmark" : "doc.on.doc") {
                            translator.copyOutput()
                        }
                        .padding(6)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .acceptsNotchKeyboardInput()
        // The session lives here; a new configuration (or an invalidated one) runs the closure again
        .translationTask(configuration) { session in
            await run(session)
        }
        .onChange(of: translator.request) { requestTranslation() }
        .onAppear {
            if !translator.input.isEmpty {
                // Opened with text from the clipboard: just show the translation. Taking the keyboard
                // here would pull focus from the app the user is in; clicking the field still allows editing.
                requestTranslation()
            } else {
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    NotchKeyboardFocus.takeKeyboard()
                    inputFocused = true
                }
            }
        }
    }

    private func requestTranslation() {
        let source = Locale.Language(identifier: translator.source)
        let target = Locale.Language(identifier: translator.target)
        if configuration?.source == source && configuration?.target == target {
            configuration?.invalidate()
        } else {
            configuration = .init(source: source, target: target)
        }
    }

    private func run(_ session: TranslationSession) async {
        let text = translator.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        translator.isTranslating = true
        defer { translator.isTranslating = false }

        // A missing language brings up macOS's download window over the notch. The pointer then counts as having
        // left the notch, which closed it and took this panel away; keep it open until the window is done.
        let status = await LanguageAvailability().status(
            from: Locale.Language(identifier: translator.source),
            to: Locale.Language(identifier: translator.target)
        )
        let needsDownload = status != .installed
        if needsDownload { SharingStateManager.shared.beginInteraction() }
        defer {
            if needsDownload {
                SharingStateManager.shared.endInteraction()
                SharingStateManager.shared.requestCloseIfReady()
            }
        }
        do {
            if needsDownload { try await session.prepareTranslation() }
            translator.output = try await session.translate(text).targetText
        } catch {
            translator.errorMessage = "Couldn't translate: \(error.localizedDescription). The language may need downloading in System Settings › General › Language & Region › Translation Languages."
        }
    }

    private func close() {
        NotchKeyboardFocus.returnKeyboard()
        vm.close()
    }

    private func pill(_ title: LocalizedStringKey, icon: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(.caption, design: .rounded, weight: primary ? .semibold : .regular))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(primary ? Color.effectiveAccent : Color(nsColor: .secondarySystemFill)))
            .foregroundStyle(.white)
        }
        .buttonStyle(PlainButtonStyle())
        .fixedSize()
    }
}
