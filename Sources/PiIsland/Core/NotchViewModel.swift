//
//  NotchViewModel.swift
//  PiIsland
//
//  State management for the dynamic island
//

import AppKit
import Combine
import SwiftUI

enum NotchStatus: Equatable {
    case closed
    case opened
    case hint  // Subtle horizontal expansion to indicate unread response
}

enum NotchOpenReason {
    case click
    case hover
    case notification
    case boot
    case unknown
}

enum NotchContentType: Equatable {
    case sessions
    case chat(ManagedSession)
    case settings
    case usage

    var id: String {
        switch self {
        case .sessions: return "sessions"
        case .chat(let session): return "chat-\(session.id)"
        case .settings: return "settings"
        case .usage: return "usage"
        }
    }

    static func == (lhs: NotchContentType, rhs: NotchContentType) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
@Observable
class NotchViewModel {
    // MARK: - Observable State

    var status: NotchStatus = .closed {
        didSet {
            if status != oldValue {
                onStatusChange?(status)
            }
        }
    }
    var openReason: NotchOpenReason = .unknown
    var contentType: NotchContentType = .sessions
    var isHovering: Bool = false

    // MARK: - Dependencies

    let sessionManager: SessionManager

    // MARK: - Geometry

    private(set) var geometry: NotchGeometry
    private(set) var hasPhysicalNotch: Bool

    var deviceNotchRect: CGRect { geometry.deviceNotchRect }
    var screenRect: CGRect { geometry.screenRect }
    var windowHeight: CGFloat { geometry.windowHeight }

    /// Dynamic opened size based on content type
    var openedSize: CGSize {
        switch contentType {
        case .chat:
            return CGSize(
                width: min(screenRect.width * 0.5, 500),
                height: 480
            )
        case .sessions:
            return CGSize(
                width: min(screenRect.width * 0.4, 400),
                height: 320
            )
        case .settings:
            return CGSize(
                width: min(screenRect.width * 0.4, 400),
                height: 220
            )
        case .usage:
            return CGSize(
                width: min(screenRect.width * 0.4, 420),
                height: 400
            )
        }
    }

    /// Maximum panel size for hit testing (prevents race conditions when content type changes)
    private var maxOpenedSize: CGSize {
        CGSize(
            width: min(screenRect.width * 0.5, 500),
            height: 480
        )
    }

    /// Size of the closed notch
    var closedNotchSize: CGSize {
        CGSize(
            width: deviceNotchRect.width,
            height: deviceNotchRect.height
        )
    }

    /// Size of the hint state - same as closed (no width change)
    var hintNotchSize: CGSize {
        closedNotchSize
    }

    // MARK: - Animation

    var animation: Animation {
        .easeOut(duration: 0.25)
    }

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private let events = EventMonitors.shared
    private var hoverTimer: DispatchWorkItem?
    private var hintTimer: DispatchWorkItem?
    private var currentChatSession: ManagedSession?

    /// Session that has an unread response
    private(set) var unreadSession: ManagedSession?

    /// Callback for when agent completes - used to trigger bounce animation
    var onAgentCompletedForBounce: (() -> Void)?

    /// Callback for when status changes - used by window controller
    var onStatusChange: ((NotchStatus) -> Void)?

    // MARK: - Initialization

    init(geometry: NotchGeometry, hasPhysicalNotch: Bool, sessionManager: SessionManager) {
        self.geometry = geometry
        self.hasPhysicalNotch = hasPhysicalNotch
        self.sessionManager = sessionManager
        setupEventHandlers()
        setupAgentCompletionHandler()
        updateTrackingState()
    }

    /// Update geometry when screen changes (external display handling)
    func updateGeometry(_ newGeometry: NotchGeometry, hasPhysicalNotch: Bool) {
        self.geometry = newGeometry
        self.hasPhysicalNotch = hasPhysicalNotch
        updateTrackingState()
    }

    /// Update the mouse tracking region for battery efficiency
    private func updateTrackingState() {
        // Set whether detailed tracking is needed
        events.needsDetailedTracking = (status == .opened || status == .hint)

        // Update the tracking region
        let notchFrame = geometry.notchScreenRect
        let openedFrame = status == .opened ? geometry.openedPanelFrame(for: openedSize) : nil
        events.updateTrackingRegion(notchFrame: notchFrame, openedFrame: openedFrame)
    }

    private func setupAgentCompletionHandler() {
        sessionManager.onAgentCompleted = { [weak self] session in
            guard let self = self else { return }
            self.handleSessionActivity(session)
            // Trigger bounce animation in the view
            self.onAgentCompletedForBounce?()
        }

        sessionManager.onExternalSessionUpdated = { [weak self] session in
            guard let self = self else { return }
            self.handleSessionActivity(session)
        }

        sessionManager.onSessionResumed = { [weak self] oldSession, newSession in
            guard let self = self else { return }
            if case .chat(let current) = self.contentType, current.id == oldSession.id {
                self.contentType = .chat(newSession)
                self.currentChatSession = newSession
            }
        }
    }

    private func handleSessionActivity(_ session: ManagedSession) {
        // Only show hint if notch is closed and we're not viewing this session
        guard self.status == .closed else { return }

        if case .chat(let currentSession) = self.contentType,
           currentSession.id == session.id {
            // Currently viewing this session, don't show hint
            return
        }

        // Show the hint animation
        self.notchHint(for: session)
    }

    // MARK: - Event Handling

    private func setupEventHandlers() {
        events.mouseLocation
            .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] location in
                Task { @MainActor in
                    self?.handleMouseMove(location)
                }
            }
            .store(in: &cancellables)

        events.mouseDown
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleMouseDown()
                }
            }
            .store(in: &cancellables)
    }

    private var isInDetailMode: Bool {
        switch contentType {
        case .chat, .usage, .settings:
            return true
        case .sessions:
            return false
        }
    }

    private func handleMouseMove(_ location: CGPoint) {
        let inNotch = geometry.isPointInNotch(location)
        let inOpened = status == .opened && geometry.isPointInOpenedPanel(location, size: openedSize)

        let newHovering = inNotch || inOpened

        guard newHovering != isHovering else { return }

        isHovering = newHovering

        // Cancel any pending hover timer
        hoverTimer?.cancel()
        hoverTimer = nil

        // Start hover timer to auto-expand after 1 second
        if isHovering && (status == .closed || status == .hint) {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.isHovering else { return }
                Task { @MainActor in
                    self.notchOpen(reason: .hover)
                }
            }
            hoverTimer = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
        }
    }

    private func handleMouseDown() {
        let location = NSEvent.mouseLocation

        switch status {
        case .opened:
            // Use maxOpenedSize for hit test to avoid race condition where button action
            // changes content type before this handler runs
            if geometry.isPointOutsidePanel(location, size: maxOpenedSize) {
                notchClose()
                repostClickAt(location)
            }
            // Clicks inside the panel are handled by SwiftUI buttons
        case .closed, .hint:
            if geometry.isPointInNotch(location) || geometry.isPointInHintArea(location, hintSize: hintNotchSize) {
                // Clear unread state when opening
                unreadSession = nil
                notchOpen(reason: .click)
            }
        }
    }

    /// Re-posts a mouse click at the given screen location
    private func repostClickAt(_ location: CGPoint) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let screen = NSScreen.main else { return }
            let screenHeight = screen.frame.height
            let cgPoint = CGPoint(x: location.x, y: screenHeight - location.y)

            if let mouseDown = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDown,
                mouseCursorPosition: cgPoint,
                mouseButton: .left
            ) {
                mouseDown.post(tap: .cghidEventTap)
            }

            if let mouseUp = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: cgPoint,
                mouseButton: .left
            ) {
                mouseUp.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - Actions

    func notchOpen(reason: NotchOpenReason = .unknown) {
        // Clear hint timer if active
        hintTimer?.cancel()
        hintTimer = nil

        // Clear unread state when opening
        unreadSession = nil

        openReason = reason
        status = .opened

        // Update tracking state for battery efficiency
        updateTrackingState()

        // Restore chat session if we had one
        if reason != .notification, let chatSession = currentChatSession {
            if case .chat(let current) = contentType, current.id == chatSession.id {
                return
            }
            contentType = .chat(chatSession)
        }
    }

    func notchClose() {
        // Save chat session before closing
        if case .chat(let session) = contentType {
            currentChatSession = session
        }
        status = .closed
        // Preserve usage view - only reset chat/settings to sessions
        switch contentType {
        case .chat, .settings:
            contentType = .sessions
        case .sessions, .usage:
            // Keep current view
            break
        }

        // Update tracking state for battery efficiency
        updateTrackingState()
    }

    /// Show a subtle hint that there's an unread response
    func notchHint(for session: ManagedSession) {
        guard status == .closed else { return }

        // Cancel any existing hint timer
        hintTimer?.cancel()

        unreadSession = session
        status = .hint

        // Auto-collapse after 3 seconds
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.status == .hint else { return }
            self.notchUnhint()
        }
        hintTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
    }

    func notchUnhint() {
        guard status == .hint else { return }
        hintTimer?.cancel()
        hintTimer = nil
        status = .closed
    }

    /// Clear unread state for a session
    func clearUnread(for session: ManagedSession) {
        if unreadSession?.id == session.id {
            unreadSession = nil
            if status == .hint {
                notchUnhint()
            }
        }
    }

    func showChat(for session: ManagedSession) {
        if case .chat(let current) = contentType, current.id == session.id {
            return
        }
        clearUnread(for: session)
        contentType = .chat(session)
        sessionManager.selectedSessionId = session.id
    }

    func exitChat() {
        currentChatSession = nil
        contentType = .sessions
    }

    func showSettings() {
        contentType = .settings
    }

    func exitSettings() {
        contentType = .sessions
    }

    func showUsage() {
        contentType = .usage
    }

    func exitUsage() {
        contentType = .sessions
    }

    /// Perform boot animation: expand briefly then collapse
    func performBootAnimation() {
        notchOpen(reason: .boot)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, self.openReason == .boot else { return }
            self.notchClose()
        }
    }
}
