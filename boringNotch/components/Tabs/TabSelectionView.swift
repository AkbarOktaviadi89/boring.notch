//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    var id: NotchViews { view }
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
    TabModel(label: "Focus", icon: "timer", view: .focus),
    TabModel(label: "To-do", icon: "checklist", view: .todo),
    TabModel(label: "Notes", icon: "note.text", view: .notes),
    TabModel(label: "Dev Tools", icon: "hammer.fill", view: .devTools),
    TabModel(label: "Monitor", icon: "gauge.with.dots.needle.33percent", view: .devServers)
]

/// Which side of the physical notch a row of tabs sits on
enum TabSide {
    case leading, trailing
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.boringShelf) var boringShelf
    @Default(.focusTimerEnabled) var focusTimerEnabled
    @Default(.todoEnabled) var todoEnabled
    @Default(.notesEnabled) var notesEnabled
    @Default(.devToolsEnabled) var devToolsEnabled
    @Default(.devServersEnabled) var devServersEnabled
    let side: TabSide
    /// Shared by both rows, so the selection capsule slides across the notch
    let animation: Namespace.ID

    private var visibleTabs: [TabModel] {
        tabs.filter { tab in
            switch tab.view {
            case .home: return true
            case .shelf: return boringShelf
            case .focus: return focusTimerEnabled
            case .todo: return todoEnabled
            case .notes: return notesEnabled
            case .devTools: return devToolsEnabled
            case .devServers: return devServersEnabled
            }
        }
    }

    /// Up to 3 tabs stay left of the notch; beyond that the later half moves to the right of it
    private var sideTabs: [TabModel] {
        let all = visibleTabs
        let leadingCount = all.count <= 3 ? all.count : (all.count + 1) / 2
        return side == .leading ? Array(all.prefix(leadingCount)) : Array(all.dropFirst(leadingCount))
    }

    var body: some View {
        // Each row shares its side of the notch with other controls, so squeeze the padding to fit
        GeometryReader { geo in
            tabRow(horizontalPadding: horizontalPadding(for: geo.size.width))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: side == .leading ? .leading : .trailing)
        }
    }

    private func horizontalPadding(for availableWidth: CGFloat) -> CGFloat {
        // Widest SF Symbols here (house, gauge) are about 20pt
        let iconWidth: CGFloat = 20
        let count = CGFloat(max(sideTabs.count, 1))
        let fitting = (availableWidth - count * iconWidth) / (2 * count)
        return min(15, max(3, fitting.rounded(.down)))
    }

    private func tabRow(horizontalPadding: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(sideTabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view, horizontalPadding: horizontalPadding) {
                        withAnimation(.smooth) {
                            // A tab click leaves any shortcut panel
                            coordinator.overlay = nil
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
