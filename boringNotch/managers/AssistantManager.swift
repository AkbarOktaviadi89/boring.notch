//
//  AssistantManager.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-30.
//

import AppKit
import Combine
import Foundation
import FoundationModels
import Translation

/// Summaries, rewrites and to-do lists from Apple's on-device model. The model doesn't take Indonesian yet,
/// so Indonesian text goes through the on-device translator to English and the answer comes back the same way.
@MainActor
final class AssistantManager: ObservableObject {
    static let shared = AssistantManager()

    struct SuggestedTask: Identifiable, Equatable {
        let id = UUID()
        var title: String
        var due: Date?
        var isSelected = true
    }

    @Published var input = ""
    @Published private(set) var action: AssistantAction = .summarize
    @Published private(set) var output = ""
    @Published var tasks: [SuggestedTask] = []
    @Published private(set) var status: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var wasCut = false
    @Published private(set) var didCopy = false

    private var work: Task<Void, Never>?
    private var copiedResetTask: Task<Void, Never>?

    private init() {}

    /// Why the model can't run on this Mac, or nil when it can
    static var unavailableReason: String? {
        guard #available(macOS 26.0, *) else { return "Needs macOS 26 with Apple Intelligence." }
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings › Apple Intelligence & Siri."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still getting ready (downloading). Try again in a while."
        case .unavailable(.deviceNotEligible):
            return "This Mac doesn't support Apple Intelligence."
        case .unavailable:
            return "Apple Intelligence isn't available right now."
        }
    }

    static var isAvailable: Bool { unavailableReason == nil }

    func load(_ text: String, action: AssistantAction = .summarize) {
        input = text
        run(action)
    }

    func loadClipboard(action: AssistantAction = .summarize) {
        if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
            load(text, action: action)
        }
    }

    func run(_ action: AssistantAction) {
        self.action = action
        output = ""
        tasks = []
        errorMessage = nil
        work?.cancel()
        let (text, cut) = AssistantPlan.clipped(input)
        wasCut = cut
        guard !text.isEmpty else { return }
        if let reason = Self.unavailableReason {
            errorMessage = reason
            return
        }
        work = Task { [weak self] in
            guard #available(macOS 26.0, *) else { return }
            await self?.perform(action, on: text)
        }
    }

    @available(macOS 26.0, *)
    private func perform(_ action: AssistantAction, on text: String) async {
        defer { status = nil }
        let indonesian = TranslateManager.detectLanguage(text)?.hasPrefix(TranslationPlan.home) == true
        do {
            var english = text
            if indonesian {
                status = "Translating to English…"
                english = try await translate(text, from: TranslationPlan.home, to: TranslationPlan.foreign)
            }
            guard !Task.isCancelled else { return }
            status = "Thinking…"
            let session = LanguageModelSession(instructions: action.instructions)

            if action == .todos {
                let today = Date().formatted(.dateTime.weekday(.wide).year().month(.wide).day())
                let prompt = "Today is \(today). Due dates are written as yyyy-MM-dd.\n\nText:\n\(english)"
                let found = try await session.respond(to: prompt, generating: TaskList.self).content.tasks
                var suggestions: [SuggestedTask] = []
                for task in found where !task.title.trimmingCharacters(in: .whitespaces).isEmpty {
                    var title = task.title
                    if indonesian {
                        status = "Translating back…"
                        title = (try? await translate(title, from: TranslationPlan.foreign, to: TranslationPlan.home)) ?? title
                    }
                    suggestions.append(SuggestedTask(title: title, due: AssistantPlan.dueDate(task.due)))
                }
                tasks = suggestions
                if suggestions.isEmpty { errorMessage = "No tasks found in this text." }
                return
            }

            var answer = try await session.respond(to: english).content
            if indonesian {
                status = "Translating back…"
                answer = try await translate(answer, from: TranslationPlan.foreign, to: TranslationPlan.home)
            }
            guard !Task.isCancelled else { return }
            output = AssistantPlan.tidy(answer)
        } catch is CancellationError {
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize:
                errorMessage = "The text is too long for the on-device model. Try a shorter part."
            case .unsupportedLanguageOrLocale:
                errorMessage = "The on-device model doesn't support this text's language yet."
            case .guardrailViolation:
                errorMessage = "Apple's model declined this text."
            default:
                errorMessage = "The model couldn't answer: \(error.localizedDescription)"
            }
        } catch {
            errorMessage = indonesian
                ? "Couldn't translate: \(error.localizedDescription). Download Indonesian ↔ English once in the Translate panel (⌃⌥⌘L)."
                : error.localizedDescription
        }
    }

    @available(macOS 26.0, *)
    private func translate(_ text: String, from source: String, to target: String) async throws -> String {
        let session = TranslationSession(installedSource: Locale.Language(identifier: source), target: Locale.Language(identifier: target))
        return try await session.translate(text).targetText
    }

    // MARK: - Results

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

    /// Adds the ticked tasks to To-do; returns how many
    @discardableResult
    func addSelectedTasks() -> Int {
        let chosen = tasks.filter(\.isSelected)
        for task in chosen {
            TodoManager.shared.add(title: task.title, due: task.due.map { Calendar.current.startOfDay(for: $0) })
        }
        tasks.removeAll { $0.isSelected }
        return chosen.count
    }
}

@available(macOS 26.0, *)
@Generable
struct TaskList {
    @Guide(description: "The tasks the reader has to do, in the order they appear")
    var tasks: [FoundTask]
}

@available(macOS 26.0, *)
@Generable
struct FoundTask {
    @Guide(description: "The whole task in 3 to 8 words: a verb plus what it is about, for example \"Send the project proposal to Mr. Budi\" or \"Pay the class fund\"")
    var title: String
    @Guide(description: "The due date as yyyy-MM-dd when the text gives one, otherwise an empty string")
    var due: String
}
