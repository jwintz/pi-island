//
//  NotchWindowController.swift
//  PiIsland
//
//  Controls the notch window positioning and lifecycle
//

import AppKit
import Combine
import SwiftUI

class NotchWindowController: NSWindowController {
    let viewModel: NotchViewModel
    private var currentScreen: NSScreen
    private var cancellables = Set<AnyCancellable>()

    init(screen: NSScreen, sessionManager: SessionManager) {
        self.currentScreen = screen

        let geometry = Self.createGeometry(for: screen)
        let windowFrame = Self.createWindowFrame(for: screen)

        // Create view model
        self.viewModel = NotchViewModel(
            geometry: geometry,
            hasPhysicalNotch: screen.hasPhysicalNotch,
            sessionManager: sessionManager
        )

        // Create the window
        let notchWindow = NotchPanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init(window: notchWindow)

        // Create the SwiftUI view
        let hostingController = NotchViewController(viewModel: viewModel)
        notchWindow.contentViewController = hostingController

        notchWindow.setFrame(windowFrame, display: true)

        // Escape key closes the notch
        notchWindow.onEscapePressed = { [weak viewModel] in
            guard let viewModel, viewModel.status == .opened else { return }
            viewModel.notchClose()
        }

        // Toggle mouse event handling based on notch state
        viewModel.onStatusChange = { [weak notchWindow, weak viewModel] status in
            switch status {
            case .opened:
                notchWindow?.ignoresMouseEvents = false
                // Make window key and activate app for input and tooltips
                if viewModel?.openReason != .notification {
                    NSApp.activate()
                    notchWindow?.makeKeyAndOrderFront(nil)
                }
            case .closed, .hint:
                notchWindow?.ignoresMouseEvents = true
            }
        }

        // Start with ignoring mouse events
        notchWindow.ignoresMouseEvents = true

        // Boot animation after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.viewModel.performBootAnimation()
        }
    }

    // MARK: - Screen Updates

    /// Update the window and view model for a new screen
    func updateForScreen(_ newScreen: NSScreen) {
        guard newScreen != currentScreen else { return }
        currentScreen = newScreen

        let geometry = Self.createGeometry(for: newScreen)
        let windowFrame = Self.createWindowFrame(for: newScreen)

        // Update view model geometry
        viewModel.updateGeometry(geometry, hasPhysicalNotch: newScreen.hasPhysicalNotch)

        // Reposition window
        window?.setFrame(windowFrame, display: true)
    }

    // MARK: - Geometry Helpers

    private static func createGeometry(for screen: NSScreen) -> NotchGeometry {
        let screenFrame = screen.frame
        let notchSize = screen.notchSize
        let windowHeight: CGFloat = 600

        // Device notch rect - positioned at center
        let deviceNotchRect = CGRect(
            x: (screenFrame.width - notchSize.width) / 2,
            y: 0,
            width: notchSize.width,
            height: notchSize.height
        )

        return NotchGeometry(
            deviceNotchRect: deviceNotchRect,
            screenRect: screenFrame,
            windowHeight: windowHeight
        )
    }

    private static func createWindowFrame(for screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let windowHeight: CGFloat = 600

        return NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.maxY - windowHeight,
            width: screenFrame.width,
            height: windowHeight
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - NotchPanel

class NotchPanel: NSPanel {
    /// Callback invoked when the Escape key is pressed while the panel is key
    var onEscapePressed: (() -> Void)?

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)

        // Floating panel behavior - critical for proper click handling
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false  // Must be false to accept clicks when launched from Finder

        // Transparent configuration
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        hasShadow = false

        // Prevent window from moving
        isMovable = false

        // Window behavior - stays on all spaces, above menu bar
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]

        // Above the menu bar
        level = .mainMenu + 3

        // Enable tooltips even when app is inactive
        allowsToolTipsWhenApplicationIsInactive = true

        isReleasedWhenClosed = true
        acceptsMouseMovedEvents = false
    }

    override func cancelOperation(_ sender: Any?) {
        onEscapePressed?()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - NotchViewController

class NotchViewController: NSHostingController<NotchView> {
    init(viewModel: NotchViewModel) {
        super.init(rootView: NotchView(viewModel: viewModel))
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
    }
}
