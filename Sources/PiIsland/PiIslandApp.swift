//
//  PiIslandApp.swift
//  PiIsland
//
//  App entry point and delegates
//

import SwiftUI
import AppKit
import OSLog

private let logger = Logger(subsystem: "com.pi-island", category: "App")

// MARK: - App Entry Point

@main
struct PiIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: NotchWindowController?
    var statusBarController: StatusBarController?
    var sessionManager: SessionManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply dock visibility preference
        let showInDock = UserDefaults.standard.bool(forKey: "showInDock")
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)

        // Create session manager
        sessionManager = SessionManager()

        // Get the screen with the notch (or main screen)
        guard let screen = NSScreen.builtin ?? NSScreen.main else {
            logger.error("No screen found")
            return
        }

        // Create window controller
        windowController = NotchWindowController(screen: screen, sessionManager: sessionManager!)
        windowController?.showWindow(nil)

        // Create status bar
        statusBarController = StatusBarController(sessionManager: sessionManager!)

        // Load historical sessions
        Task { @MainActor in
            await sessionManager?.loadHistoricalSessions()
        }

        logger.info("Pi Island started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task {
            if let manager = sessionManager {
                for session in manager.liveSessions {
                    await session.stop()
                }
            }
        }
    }
}

// MARK: - Status Bar Controller

@MainActor
class StatusBarController {
    private var statusItem: NSStatusItem?
    private var sessionManager: SessionManager

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = createPiLogoImage(size: 16)
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit Pi Island", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func quit() {
        Task {
            for session in sessionManager.liveSessions {
                await session.stop()
            }
            NSApp.terminate(nil)
        }
    }

    private func createPiLogoImage(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let scale = size / 800
            
            let path = NSBezierPath()
            
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                // Flip Y coordinate for AppKit
                NSPoint(x: x * scale, y: (800 - y) * scale)
            }
            
            // P shape outer boundary
            path.move(to: point(165.29, 165.29))
            path.line(to: point(517.36, 165.29))
            path.line(to: point(517.36, 400))
            path.line(to: point(400, 400))
            path.line(to: point(400, 517.36))
            path.line(to: point(282.65, 517.36))
            path.line(to: point(282.65, 634.72))
            path.line(to: point(165.29, 634.72))
            path.close()
            
            // P shape inner hole
            path.move(to: point(282.65, 282.65))
            path.line(to: point(282.65, 400))
            path.line(to: point(400, 400))
            path.line(to: point(400, 282.65))
            path.close()
            
            // i dot
            path.move(to: point(517.36, 400))
            path.line(to: point(634.72, 400))
            path.line(to: point(634.72, 634.72))
            path.line(to: point(517.36, 634.72))
            path.close()
            
            path.windingRule = .evenOdd
            NSColor.black.setFill()
            path.fill()
            
            return true
        }
        return image
    }
}
