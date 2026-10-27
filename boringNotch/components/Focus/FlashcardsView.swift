//
//  FlashcardsView.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import SwiftUI

/// Review due flashcards, or add new ones
struct FlashcardsView: View {
    @ObservedObject var manager = FlashcardManager.shared
    @State private var isAdding = false
    @State private var addedMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case front
        case back
    }

    var body: some View {
        // Refresh every 30 seconds so cards answered "Again" come back on time
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let due = manager.dueCards(at: context.date)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    FocusSectionPicker()
                    Text("\(due.count) due · \(manager.cards.count) cards")
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .monospacedDigit()
                    Spacer()
                    Button {
                        withAnimation(.smooth) {
                            isAdding.toggle()
                            addedMessage = nil
                        }
                    } label: {
                        Label(isAdding ? "Done" : "Add", systemImage: isAdding ? "checkmark" : "plus")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color(nsColor: .secondarySystemFill)))
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                if isAdding {
                    addForm
                } else if let card = due.first {
                    review(card)
                } else {
                    emptyState(now: context.date)
                }
            }
        }
        .acceptsNotchKeyboardInput()
    }

    // MARK: - Review

    private func review(_ card: Flashcard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.front)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .textSelection(.enabled)
                    if manager.isRevealed {
                        Divider().overlay(Color.white.opacity(0.15))
                        Text(card.back)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .allowsScrollingInOpenNotch()
            .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                if manager.isRevealed {
                    pillButton("Again", icon: "arrow.uturn.backward", fill: Color.orange.opacity(0.5)) {
                        withAnimation(.smooth) { manager.review(card, remembered: false) }
                    }
                    .help("Show it again in 10 minutes")
                    pillButton("Good", icon: "checkmark", fill: Color.effectiveAccent) {
                        withAnimation(.smooth) { manager.review(card, remembered: true) }
                    }
                    .help(nextIntervalHelp(card))
                } else {
                    pillButton("Show answer", icon: "eye", fill: Color.effectiveAccent) {
                        withAnimation(.smooth) { manager.isRevealed = true }
                    }
                }
                Spacer()
                Text("Box \(card.box)")
                    .font(.caption2)
                    .foregroundStyle(.gray)
                Button {
                    withAnimation(.smooth) { manager.delete(card) }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Delete this card")
            }
        }
    }

    private func nextIntervalHelp(_ card: Flashcard) -> String {
        let nextBox = min(Leitner.maxBox, card.box + 1)
        let days = Int((Leitner.intervals[nextBox] ?? 0) / 86_400)
        return days == 1 ? "Show it again tomorrow" : "Show it again in \(days) days"
    }

    private func emptyState(now: Date) -> some View {
        VStack(spacing: 4) {
            Image(systemName: manager.cards.isEmpty ? "rectangle.stack.badge.plus" : "checkmark.seal")
                .font(.title2)
            if manager.cards.isEmpty {
                Text("No cards yet. Add terms, syntax or payloads to learn.")
                    .font(.callout)
            } else if let next = manager.nextDueDate(after: now) {
                Text("All caught up. Next card \(next.formatted(.relative(presentation: .named)))")
                    .font(.callout)
            }
        }
        .foregroundStyle(.gray)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Add

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                field("Front: term or question", text: $manager.draftFront, field: .front) {
                    focusedField = .back
                }
                field("Back: answer, syntax or payload", text: $manager.draftBack, field: .back) {
                    manager.addDraft()
                    focusedField = .front
                }
                pillButton("Add", icon: "plus", fill: Color.effectiveAccent) {
                    manager.addDraft()
                    focusedField = .front
                }
            }
            HStack(spacing: 8) {
                pillButton("Paste list", icon: "doc.on.clipboard", fill: Color(nsColor: .secondarySystemFill)) {
                    let count = manager.addFromClipboard()
                    addedMessage = count == 1 ? "Added 1 card" : "Added \(count) cards"
                }
                Text(addedMessage ?? "One card per line: front :: back")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
        }
    }

    private func field(_ placeholder: LocalizedStringKey, text: Binding<String>, field: Field, onSubmit: @escaping () -> Void) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.callout)
            .focused($focusedField, equals: field)
            .onSubmit(onSubmit)
            .onExitCommand {
                focusedField = nil
                NotchKeyboardFocus.returnKeyboard()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color(nsColor: .secondarySystemFill)))
    }

    private func pillButton(_ title: LocalizedStringKey, icon: String, fill: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(fill))
                .foregroundStyle(.white)
        }
        .buttonStyle(PlainButtonStyle())
        .fixedSize()
    }
}

#Preview {
    FlashcardsView()
        .environmentObject(BoringViewModel())
        .frame(width: 600, height: 130)
        .background(.black)
}
