//
//  TodoView.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-27.
//

import AppKit
import SwiftUI

struct TodoView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var todo = TodoManager.shared
    @FocusState private var isFieldFocused: Bool
    @State private var hostWindow: NSWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            list
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WindowReader(window: $hostWindow))
        .onChange(of: vm.notchState) { _, state in
            if state == .closed { NotchKeyboardFocus.end(in: hostWindow) }
        }
        .onDisappear {
            NotchKeyboardFocus.end(in: hostWindow)
        }
        .onAppear {
            NotchKeyboardFocus.allow()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.effectiveAccent)
                TextField("Add a task and press Return", text: $todo.draft)
                    .textFieldStyle(.plain)
                    .focused($isFieldFocused)
                    .onSubmit {
                        todo.addDraft()
                    }
                    .onExitCommand {
                        isFieldFocused = false
                        NotchKeyboardFocus.returnKeyboard(from: hostWindow)
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color(nsColor: .secondarySystemFill)))

            Text("\(todo.remainingCount) left")
                .font(.caption)
                .foregroundStyle(.gray)
                .monospacedDigit()

            if todo.hasCompleted {
                Button("Clear done") {
                    withAnimation(.smooth) { todo.clearCompleted() }
                }
                .font(.caption)
                .buttonStyle(PlainButtonStyle())
                .foregroundStyle(.gray)
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if todo.items.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "checklist")
                    .font(.title2)
                Text("No tasks yet")
                    .font(.callout)
            }
            .foregroundStyle(.gray)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(todo.sortedItems) { item in
                        TodoRow(item: item)
                    }
                }
                .animation(.smooth, value: todo.sortedItems)
            }
        }
    }
}

private struct TodoRow: View {
    let item: TodoItem
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.smooth) { TodoManager.shared.toggle(item.id) }
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(item.isDone ? Color.effectiveAccent : .gray)
            }
            .buttonStyle(PlainButtonStyle())

            Text(item.title)
                .font(.callout)
                .strikethrough(item.isDone)
                .foregroundStyle(item.isDone ? .gray : .white)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Button {
                withAnimation(.smooth) { TodoManager.shared.delete(item.id) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
            }
            .buttonStyle(PlainButtonStyle())
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.white.opacity(0.06) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

/// Exposes the NSWindow hosting a SwiftUI view
private struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if window !== nsView.window {
            DispatchQueue.main.async {
                window = nsView.window
            }
        }
    }
}

#Preview {
    TodoView()
        .environmentObject(BoringViewModel())
        .frame(width: 600, height: 150)
        .background(.black)
}
