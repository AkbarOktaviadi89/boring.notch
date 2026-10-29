//
//  AssistantView.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-30.
//

import SwiftUI

/// ⌃⌥⌘A or the "Summarize" clipboard hint: summaries, rewrites and to-dos from Apple's on-device model
struct AssistantView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var assistant = AssistantManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                ForEach(AssistantAction.allCases) { action in
                    chip(action)
                }
                Spacer(minLength: 4)
                Text(sourceLabel)
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                Button { assistant.loadClipboard(action: assistant.action) } label: {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 11))
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundStyle(.gray)
                .help("Use what's on the clipboard now")
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05))
                content
                    .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onExitCommand { vm.close() }
    }

    private var sourceLabel: String {
        let words = AssistantPlan.wordCount(assistant.input)
        return assistant.wasCut ? "first \(AssistantPlan.maximumWords) of \(words) words" : "\(words) words"
    }

    @ViewBuilder
    private var content: some View {
        if let status = assistant.status {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(status).font(.callout).foregroundStyle(.gray)
            }
        } else if let error = assistant.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(4)
        } else if assistant.action == .todos && !assistant.tasks.isEmpty {
            taskList
        } else if !assistant.output.isEmpty {
            ScrollView(.vertical, showsIndicators: false) {
                Text(assistant.output)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 70)
            }
            .allowsScrollingInOpenNotch()
            .overlay(alignment: .topTrailing) {
                pill(assistant.didCopy ? "Copied" : "Copy", icon: assistant.didCopy ? "checkmark" : "doc.on.doc", primary: true) {
                    assistant.copyOutput()
                }
            }
        } else if assistant.input.isEmpty {
            Text("Copy some text, then press ⌃⌥⌘A or pick an action. Everything runs on this Mac.")
                .font(.callout)
                .foregroundStyle(.gray)
        } else {
            Text("Pick an action above.").font(.callout).foregroundStyle(.gray)
        }
    }

    private var taskList: some View {
        HStack(alignment: .top, spacing: 8) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach($assistant.tasks) { $task in
                        HStack(spacing: 6) {
                            Button { task.isSelected.toggle() } label: {
                                Image(systemName: task.isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.isSelected ? Color.effectiveAccent : .gray)
                            }
                            .buttonStyle(PlainButtonStyle())
                            Text(task.title)
                                .font(.callout)
                                .lineLimit(1)
                            if let due = task.due {
                                Text(TodoSchedule.dueLabel(due, now: Date()))
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.effectiveAccent.opacity(0.2)))
                                    .foregroundStyle(Color.effectiveAccent)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .allowsScrollingInOpenNotch()
            pill("Add to To-do", icon: "plus", primary: true) {
                let added = assistant.addSelectedTasks()
                BoringViewCoordinator.shared.showToast(icon: "checklist", title: "To-do", detail: "+\(added)", tint: .green)
            }
            .disabled(!assistant.tasks.contains(where: \.isSelected))
        }
    }

    private func chip(_ action: AssistantAction) -> some View {
        let isOn = assistant.action == action
        return Button { assistant.run(action) } label: {
            HStack(spacing: 4) {
                Image(systemName: action.icon)
                Text(action.rawValue)
            }
            .font(.system(.caption, design: .rounded, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(isOn ? Color.effectiveAccent.opacity(0.35) : Color(nsColor: .secondarySystemFill)))
            .foregroundStyle(isOn ? .white : .gray)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(assistant.input.isEmpty)
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
