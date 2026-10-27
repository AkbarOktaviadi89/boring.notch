//
//  BoringNotchSkyLightWindow.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-20.
//

import Cocoa
import SkyLightWindow
import Defaults
import Combine
import SwiftUI

extension SkyLightOperator {
    func undelegateWindow(_ window: NSWindow) {
        typealias F_SLSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32
        
        let handler = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
        guard let SLSRemoveWindowsFromSpaces = unsafeBitCast(
            dlsym(handler, "SLSRemoveWindowsFromSpaces"),
            to: F_SLSRemoveWindowsFromSpaces?.self
        ) else {
            return
        }
        
        // Remove the window from the SkyLight space
        _ = SLSRemoveWindowsFromSpaces(
            connection,
            [window.windowNumber] as CFArray,
            [space] as CFArray
        )
    }
}

class BoringNotchSkyLightWindow: NSPanel {
    private var isSkyLightEnabled: Bool = false
    
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        
        configureWindow()
        setupObservers()
    }
    
    private func configureWindow() {
        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        level = .mainMenu + 3
        hasShadow = false
        isReleasedWhenClosed = false
        
        // Force dark appearance regardless of system setting
        appearance = NSAppearance(named: .darkAqua)
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        
        // Apply initial sharing type setting
        updateSharingType()
    }
    
    private func setupObservers() {
        // Listen for changes to the hideFromScreenRecording setting
        Defaults.publisher(.hideFromScreenRecording)
            .sink { [weak self] _ in
                self?.updateSharingType()
            }
            .store(in: &observers)
    }
    
    private func updateSharingType() {
        if Defaults[.hideFromScreenRecording] {
            sharingType = .none
        } else {
            sharingType = .readWrite
        }
    }
    
    func enableSkyLight() {
        if !isSkyLightEnabled {
            SkyLightOperator.shared.delegateWindow(self)
            isSkyLightEnabled = true
        }
    }
    
    func disableSkyLight() {
        if isSkyLightEnabled {
            SkyLightOperator.shared.undelegateWindow(self)
            isSkyLightEnabled = false
        }
    }
    
    private var observers: Set<AnyCancellable> = []
    
    override var canBecomeKey: Bool { NotchKeyboardFocus.isActive }
    override var canBecomeMain: Bool { false }
}

/// Lets the notch window take keyboard input only while a view with a text field is showing.
/// The window is a non-activating panel, so the app the user was in stays frontmost.
/// The window only becomes key when the user clicks into it, and key focus is handed
/// back to the previous app when typing ends.
@MainActor
enum NotchKeyboardFocus {
    /// Counted rather than a flag: when switching tabs SwiftUI may show the new view
    /// before the old one disappears
    private static var holders = 0
    private static weak var window: NSWindow?
    private static var previousApp: NSRunningApplication?

    static var isActive: Bool { holders > 0 }

    /// Must happen before the click: AppKit asks `canBecomeKey` on mouse down,
    /// so allowing it from the click itself is too late.
    static func acquire() {
        if holders == 0 {
            previousApp = NSWorkspace.shared.frontmostApplication
        }
        holders += 1
    }

    static func release() {
        guard holders > 0 else { return }
        holders -= 1
        if holders == 0 {
            returnKeyboard()
            previousApp = nil
            window = nil
        }
    }

    static func setWindow(_ window: NSWindow?) {
        if let window { self.window = window }
    }

    /// Gives the keyboard back to the previous app but keeps the window allowed to take it again
    static func returnKeyboard() {
        guard let window, window.isKeyWindow else { return }
        window.makeFirstResponder(nil)
        if let previousApp, previousApp != NSRunningApplication.current {
            previousApp.activate()
        }
    }
}

extension View {
    /// Lets text fields in this view receive typing while it is on screen in the open notch
    func acceptsNotchKeyboardInput() -> some View {
        modifier(NotchKeyboardInputModifier())
    }
}

private struct NotchKeyboardInputModifier: ViewModifier {
    @EnvironmentObject var vm: BoringViewModel
    @State private var window: NSWindow?

    func body(content: Content) -> some View {
        content
            .background(WindowReader(window: $window))
            .onAppear { NotchKeyboardFocus.acquire() }
            .onDisappear { NotchKeyboardFocus.release() }
            .onChange(of: window) { _, window in
                NotchKeyboardFocus.setWindow(window)
            }
            .onChange(of: vm.notchState) { _, state in
                if state == .closed { NotchKeyboardFocus.returnKeyboard() }
            }
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
