//
//  ShelfItemView.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import SwiftUI
import AppKit

struct ShelfView: View {
    @EnvironmentObject var vm: BoringViewModel
    @StateObject var tvm = ShelfStateViewModel.shared
    @StateObject var selection = ShelfSelectionModel.shared
    @StateObject private var quickLookService = QuickLookService()
    @ObservedObject private var conversions = FileConversionService.shared
    @ObservedObject private var dragState = ShelfDragState.shared
    private let spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: 12) {
            FileShareView()
                .aspectRatio(1, contentMode: .fit)
                .environmentObject(vm)
            panel
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data],
                        delegate: ShelfDropDelegate(id: "panel", isTargeted: $vm.dragDetectorTargeting, onDrop: handleDrop))

        }
        // Dragging files in turns the whole Shelf into drop targets: add as is, or convert on the way in.
        // The whole width, not just the panel, so each tile is big enough to hit.
        .overlay {
            if dragState.isActive && !dragState.actions.isEmpty {
                ShelfConvertDropZones()
                    .environmentObject(vm)
                    .transition(.opacity)
            }
        }
        // Bind Quick Look to shelf selection
        .onChange(of: selection.selectedIDs) {
            updateQuickLookSelection()
        }
        .quickLookPresenter(using: quickLookService)
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !selection.isDragging else { return false }
        vm.dropEvent = true
        ShelfStateViewModel.shared.load(providers)
        return true
    }
    
    private func updateQuickLookSelection() {
        guard quickLookService.isQuickLookOpen && !selection.selectedIDs.isEmpty else { return }
        
        let selectedItems = selection.selectedItems(in: tvm.items)
        let urls: [URL] = selectedItems.compactMap { item in
            if let fileURL = item.fileURL {
                return fileURL
            }
            if case .link(let url) = item.kind {
                return url
            }
            return nil
        }
        
        if !urls.isEmpty {
            quickLookService.updateSelection(urls: urls)
        }
    }

    var panel: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                // A drop anywhere on the open notch lands here too, see GeneralDropTargetDelegate
                vm.dragDetectorTargeting || vm.generalDropTargeting
                    ? Color.accentColor.opacity(0.9)
                    : Color.white.opacity(0.1),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
            )
            .overlay {
                content
                    .padding()
            }
            .transaction { transaction in
                transaction.animation = vm.animation
            }
            .contentShape(Rectangle())
            .onTapGesture { selection.clear() }
            // What's being converted, or why it wasn't, across the bottom of the panel
            .overlay(alignment: .bottom) {
                if let status = conversions.status {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(status)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.effectiveAccent.opacity(0.35)))
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.9)))
                    .padding(8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let message = conversions.message {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(message)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.92)))
                    .padding(8)
                    .contentShape(Rectangle())
                    .onTapGesture { conversions.dismissMessage() }
                    .transition(.opacity)
                }
            }
            .animation(.smooth, value: conversions.status)
            .animation(.smooth, value: conversions.message)
    }

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down")
                        .symbolVariant(.fill)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.large)
                    
                    Text("Drop files here")
                        .foregroundStyle(.gray)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.medium)
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: spacing) {
                        ForEach(tvm.items) { item in
                            ShelfItemView(item: item)
                                .environmentObject(quickLookService)
                        }
                    }
                }
                .padding(-spacing)
                .scrollIndicators(.never)
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data],
                        delegate: ShelfDropDelegate(id: "items", isTargeted: $vm.dragDetectorTargeting, onDrop: handleDrop))
            }
        }
        .onAppear {
            ShelfStateViewModel.shared.cleanupInvalidItems()
        }
    }
}
