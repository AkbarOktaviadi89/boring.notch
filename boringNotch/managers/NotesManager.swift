//
//  NotesManager.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import AppKit
import Combine
import Defaults

extension Note: Defaults.Serializable {}

@MainActor
final class NotesManager: ObservableObject {
    static let shared = NotesManager()

    @Published private(set) var notes: [Note] = Defaults[.notes] {
        didSet { Defaults[.notes] = notes }
    }
    @Published var selectedID: Note.ID? = Defaults[.notesSelectedID] {
        didSet {
            Defaults[.notesSelectedID] = selectedID
            if let oldValue, oldValue != selectedID { removeIfBlank(oldValue) }
        }
    }
    /// Search text, kept when the notch closes
    @Published var query = ""

    private init() {
        // A note left empty when the app quit isn't worth keeping
        notes.removeAll { $0.isBlank && $0.id != selectedID }
        if selectedID.flatMap(note(with:)) == nil { selectedID = visibleNotes.first?.id }
    }

    var visibleNotes: [Note] {
        NoteText.search(notes, query: query)
    }

    var selectedNote: Note? {
        selectedID.flatMap(note(with:))
    }

    func note(with id: Note.ID) -> Note? {
        notes.first { $0.id == id }
    }

    @discardableResult
    func create(text: String = "") -> Note {
        let note = Note(text: text)
        notes.append(note)
        query = ""
        selectedID = note.id
        return note
    }

    /// Creates a note from the clipboard text; returns false when the clipboard holds no text
    @discardableResult
    func createFromClipboard() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        create(text: text)
        return true
    }

    func update(_ id: Note.ID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].text != text else { return }
        notes[index].text = text
        notes[index].updatedAt = Date()
    }

    func togglePin(_ id: Note.ID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isPinned.toggle()
    }

    func duplicate(_ id: Note.ID) {
        guard let original = note(with: id) else { return }
        create(text: original.text)
    }

    func copy(_ id: Note.ID) {
        guard let note = note(with: id) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.text, forType: .string)
    }

    func delete(_ id: Note.ID) {
        let wasSelected = selectedID == id
        notes.removeAll { $0.id == id }
        if wasSelected { selectedID = visibleNotes.first?.id }
    }

    func deleteAll() {
        notes = []
        selectedID = nil
    }

    /// Called when the tab goes away, so an untouched "New note" doesn't linger in the list
    func discardSelectedIfBlank() {
        guard let id = selectedID, note(with: id)?.isBlank == true else { return }
        notes.removeAll { $0.id == id }
        selectedID = visibleNotes.first?.id
    }

    private func removeIfBlank(_ id: Note.ID) {
        if note(with: id)?.isBlank == true { notes.removeAll { $0.id == id } }
    }
}
