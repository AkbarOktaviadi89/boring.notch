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
    TabModel(label: "Dev Tools", icon: "hammer.fill", view: .devTools),
    TabModel(label: "Monitor", icon: "gauge.with.dots.needle.33percent", view: .devServers)
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Default(.boringShelf) var boringShelf
    @Default(.focusTimerEnabled) var focusTimerEnabled
    @Default(.todoEnabled) var todoEnabled
    @Default(.devToolsEnabled) var devToolsEnabled
    @Default(.devServersEnabled) var devServersEnabled
    @Namespace var animation

    private var visibleTabs: [TabModel] {
        tabs.filter { tab in
            switch tab.view {
            case .home: return true
            case .shelf: return boringShelf
            case .focus: return focusTimerEnabled
            case .todo: return todoEnabled
            case .devTools: return devToolsEnabled
            case .devServers: return devServersEnabled
            }
        }
    }

    var body: some View {
        // The tabs share the space left of the physical notch, so squeeze the padding as tabs are added
        GeometryReader { geo in
            tabRow(horizontalPadding: horizontalPadding(for: geo.size.width))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func horizontalPadding(for availableWidth: CGFloat) -> CGFloat {
        let iconWidth: CGFloat = 18
        let count = CGFloat(max(visibleTabs.count, 1))
        let fitting = (availableWidth - count * iconWidth) / (2 * count)
        return min(15, max(5, fitting.rounded(.down)))
    }

    private func tabRow(horizontalPadding: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view, horizontalPadding: horizontalPadding) {
                        withAnimation(.smooth) {
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
