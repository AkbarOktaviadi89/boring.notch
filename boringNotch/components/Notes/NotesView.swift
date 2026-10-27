//
//  NotesView.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import Defaults
import SwiftUI

struct NotesView: View {
    @ObservedObject var notes = NotesManager.shared
    @FocusState private var focus: Field?
    @State private var didCopy = false

    private enum Field {
        case search, editor
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            sidebar
                .frame(width: 190)
            editor
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .acceptsNotchKeyboardInput()
        .onDisappear { notes.discardSelectedIfBlank() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    TextField("Search", text: $notes.query)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .focused($focus, equals: .search)
                        .onExitCommand(perform: releaseKeyboard)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(nsColor: .secondarySystemFill)))

                iconButton("square.and.pencil", help: "New note", tint: .effectiveAccent) {
                    withAnimation(.smooth) { notes.create() }
                    focus = .editor
                }
            }

            if notes.visibleNotes.isEmpty {
                Text(notes.query.isEmpty ? "No notes yet" : "No matches")
                    .font(.callout)
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Re-render every minute so "14:05" turns into "Yesterday" while the tab stays open
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(notes.visibleNotes) { note in
                                NoteRow(note: note, isSelected: note.id == notes.selectedID, now: context.date) {
                                    notes.selectedID = note.id
                                }
                            }
                        }
                        .animation(.smooth, value: notes.visibleNotes)
                    }
                    .allowsScrollingInOpenNotch()
                }
            }
        }
    }

    // MARK: - Editor

    @ViewBuilder
    private var editor: some View {
        if let note = notes.selectedNote {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("\(NoteText.dateLabel(note.updatedAt, now: Date())) · \(NoteText.wordCount(of: note.text)) words")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    Spacer()
                    iconButton(note.isPinned ? "pin.fill" : "pin", help: note.isPinned ? "Unpin" : "Pin to top",
                               tint: note.isPinned ? .effectiveAccent : .gray) {
                        withAnimation(.smooth) { notes.togglePin(note.id) }
                    }
                    iconButton(didCopy ? "checkmark" : "doc.on.doc", help: "Copy note", tint: .gray) {
                        notes.copy(note.id)
                        flashCopied()
                    }
                    .disabled(note.isBlank)
                    iconButton("trash", help: "Delete note", tint: .gray) {
                        withAnimation(.smooth) { notes.delete(note.id) }
                    }
                }

                TextEditor(text: Binding(
                    get: { notes.selectedNote?.text ?? "" },
                    set: { notes.update(note.id, text: $0) }
                ))
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .focused($focus, equals: .editor)
                .onExitCommand(perform: releaseKeyboard)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .secondarySystemFill)))
                .overlay(alignment: .topLeading) {
                    if note.text.isEmpty {
                        Text("Start typing. The first line becomes the title.")
                            .font(.system(size: 13))
                            .foregroundStyle(.gray)
                            .padding(.leading, 11)
                            .padding(.top, 6)
                            .allowsHitTesting(false)
                    }
                }
                .allowsScrollingInOpenNotch()
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "note.text")
                    .font(.title2)
                    .foregroundStyle(.gray)
                HStack(spacing: 6) {
                    capsuleButton("New note", icon: "square.and.pencil", primary: true) {
                        withAnimation(.smooth) { notes.create() }
                        focus = .editor
                    }
                    capsuleButton("From clipboard", icon: "doc.on.clipboard") {
                        withAnimation(.smooth) { _ = notes.createFromClipboard() }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func releaseKeyboard() {
        focus = nil
        NotchKeyboardFocus.returnKeyboard()
    }

    private func flashCopied() {
        withAnimation(.smooth) { didCopy = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.smooth) { didCopy = false }
        }
    }

    private func iconButton(_ icon: String, help: LocalizedStringKey, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .help(help)
    }

    private func capsuleButton(_ title: LocalizedStringKey, icon: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(.caption, design: .rounded, weight: primary ? .semibold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(primary ? Color.effectiveAccent : Color(nsColor: .secondarySystemFill)))
            .foregroundStyle(.white)
        }
        .buttonStyle(PlainButtonStyle())
        .fixedSize()
    }
}

private struct NoteRow: View {
    let note: Note
    let isSelected: Bool
    let now: Date
    let select: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.effectiveAccent)
                    }
                    Text(NoteText.title(of: note.text))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(note.isBlank ? .gray : .white)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    Text(NoteText.dateLabel(note.updatedAt, now: now))
                    Text(NoteText.preview(of: note.text))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.caption)
                .foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.12) : isHovering ? Color.white.opacity(0.06) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(note.isPinned ? "Unpin" : "Pin to top") {
                withAnimation(.smooth) { NotesManager.shared.togglePin(note.id) }
            }
            Button("Copy") { NotesManager.shared.copy(note.id) }
            Button("Duplicate") {
                withAnimation(.smooth) { NotesManager.shared.duplicate(note.id) }
            }
            Divider()
            Button("Delete") {
                withAnimation(.smooth) { NotesManager.shared.delete(note.id) }
            }
        }
    }
}

#Preview {
    NotesView()
        .environmentObject(BoringViewModel())
        .frame(width: 600, height: 150)
        .background(.black)
}
