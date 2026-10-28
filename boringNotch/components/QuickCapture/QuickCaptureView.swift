//
//  QuickCaptureView.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-28.
//

import SwiftUI

/// Opened by the quick-capture shortcut: type a task (or "n:" for a note), press Return, and the notch closes again.
/// The app you were typing in stays frontmost the whole time.
struct QuickCaptureView: View {
    @EnvironmentObject var vm: BoringViewModel
    @State private var text = ""
    /// Where the last entry went, shown for a moment before the notch closes
    @State private var savedTo: String?
    @FocusState private var isFocused: Bool

    private var target: CaptureTarget? {
        QuickCapture.parse(text, now: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: savedTo == nil ? "plus.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(savedTo == nil ? Color.effectiveAccent : .green)
                    .contentTransition(.symbolEffect(.replace))
                if let savedTo {
                    Text("Saved to \(savedTo)")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                } else {
                    TextField("Add a task, or start with n: for a note", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($isFocused)
                        .onSubmit(save)
                        .onExitCommand(perform: close)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .secondarySystemFill)))

            HStack(spacing: 6) {
                if let target, savedTo == nil {
                    Image(systemName: isNote(target) ? "note.text" : "checklist")
                    Text(QuickCapture.destination(of: target, now: Date()))
                        .foregroundStyle(.white.opacity(0.85))
                } else {
                    Text("End with besok, lusa or a weekday to set the date")
                }
                Spacer()
                Text("↩ Save · esc Cancel")
            }
            .font(.caption)
            .foregroundStyle(.gray)
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .acceptsNotchKeyboardInput()
        .onAppear {
            // The window is found a moment after the view appears; then take the keyboard without a click
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                NotchKeyboardFocus.takeKeyboard()
                isFocused = true
            }
        }
    }

    private func isNote(_ target: CaptureTarget) -> Bool {
        if case .note = target { return true }
        return false
    }

    private func save() {
        guard savedTo == nil, let target else { return }
        switch target {
        case .todo(let title, let due):
            TodoManager.shared.add(title: title, due: due)
        case .note(let body):
            NotesManager.shared.create(text: body)
        }
        withAnimation(.smooth) {
            savedTo = QuickCapture.destination(of: target, now: Date())
        }
        text = ""
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            close()
        }
    }

    private func close() {
        NotchKeyboardFocus.returnKeyboard()
        vm.close()
    }
}

#Preview {
    QuickCaptureView()
        .environmentObject(BoringViewModel())
        .frame(width: 600, height: 150)
        .background(.black)
}
