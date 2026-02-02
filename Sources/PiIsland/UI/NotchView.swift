//
//  NotchView.swift
//  PiIsland
//
//  The main dynamic island SwiftUI view
//

import SwiftUI
import ServiceManagement
import Combine

// Corner radius constants
private let cornerRadiusInsets = (
    opened: (top: CGFloat(19), bottom: CGFloat(24)),
    closed: (top: CGFloat(6), bottom: CGFloat(14))
)

struct NotchView: View {
    @ObservedObject var viewModel: NotchViewModel
    @State private var isVisible: Bool = false
    @State private var isHovering: Bool = false
    @State private var activityCheckTrigger: Int = 0  // Triggers re-evaluation of hasActivity

    // MARK: - Sizing

    private var notchSize: CGSize {
        switch viewModel.status {
        case .closed:
            return viewModel.closedNotchSize
        case .hint:
            return viewModel.hintNotchSize
        case .opened:
            return viewModel.openedSize
        }
    }

    // MARK: - Corner Radii

    private var topCornerRadius: CGFloat {
        viewModel.status == .opened
            ? cornerRadiusInsets.opened.top
            : cornerRadiusInsets.closed.top
    }

    private var bottomCornerRadius: CGFloat {
        viewModel.status == .opened
            ? cornerRadiusInsets.opened.bottom
            : cornerRadiusInsets.closed.bottom
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )
    }

    // Animation springs
    private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    private let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
    private let hintAnimation = Animation.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0)

    private var animationForStatus: Animation {
        switch viewModel.status {
        case .opened:
            return openAnimation
        case .hint:
            return hintAnimation
        case .closed:
            return closeAnimation
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Outer container does NOT receive hits - only the notch content does
            VStack(spacing: 0) {
                notchLayout
                    .frame(
                        maxWidth: viewModel.status == .opened ? notchSize.width : nil,
                        alignment: .top
                    )
                    .padding(
                        .horizontal,
                        viewModel.status == .opened
                            ? cornerRadiusInsets.opened.top
                            : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], viewModel.status == .opened ? 12 : 0)
                    .background(.black)
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: (viewModel.status == .opened || isHovering) ? .black.opacity(0.7) : .clear,
                        radius: 6
                    )
                    .frame(
                        maxWidth: viewModel.status == .opened ? notchSize.width : nil,
                        maxHeight: viewModel.status == .opened ? notchSize.height : nil,
                        alignment: .top
                    )
                    .animation(animationForStatus, value: viewModel.status)
                    .animation(openAnimation, value: notchSize)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                            isHovering = hovering
                        }
                    }
                    .onTapGesture {
                        if viewModel.status != .opened {
                            viewModel.notchOpen(reason: .click)
                        }
                    }
            }
        }
        .opacity(isVisible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .onAppear {
            // Always visible on non-notched devices
            if !viewModel.hasPhysicalNotch {
                isVisible = true
            }
        }
        .onChange(of: viewModel.status) { oldStatus, newStatus in
            handleStatusChange(from: oldStatus, to: newStatus)
        }
        .onChange(of: viewModel.sessionManager.liveSessions) { _, sessions in
            handleSessionsChange(sessions)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            // Periodically re-evaluate activity state for external sessions
            activityCheckTrigger += 1
        }
    }

    // MARK: - Notch Layout

    @ViewBuilder
    private var notchLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row - always present, matches physical notch height
            headerRow
                .frame(height: viewModel.closedNotchSize.height)

            // Main content only when opened
            if viewModel.status == .opened {
                contentView
                    .frame(width: notchSize.width - 24, height: notchSize.height - viewModel.closedNotchSize.height - 24)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.8, anchor: .top)
                                .combined(with: .opacity)
                                .animation(.smooth(duration: 0.35)),
                            removal: .opacity.animation(.easeOut(duration: 0.15))
                        )
                    )
            }
        }
    }

    // MARK: - Header Row

    private var hasActivity: Bool {
        // This depends on activityCheckTrigger to force re-evaluation
        _ = activityCheckTrigger

        // Check live sessions for thinking/executing
        let liveActivity = viewModel.sessionManager.liveSessions.contains { session in
            session.phase == .thinking || session.phase == .executing
        }
        // Check historical sessions for likely thinking (terminal pi)
        let externalActivity = viewModel.sessionManager.historicalSessions.contains { session in
            session.isLikelyThinking
        }
        return liveActivity || externalActivity
    }

    private var isHintState: Bool {
        viewModel.status == .hint
    }

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 0) {
            // Left side - Pi logo (pulses when there's an unread message)
            HStack(spacing: 4) {
                PiLogo(size: 14, isAnimating: hasActivity, isPulsing: isHintState)
            }
            .frame(width: viewModel.status == .opened ? sideWidth : sideWidth, alignment: .center)
            .padding(.leading, viewModel.status == .opened ? 8 : 0)

            // Center
            if viewModel.status == .opened {
                openedHeaderContent
            } else {
                // Closed/Hint: black spacer with constrained width
                Rectangle()
                    .fill(.black)
                    .frame(width: max(0, viewModel.closedNotchSize.width - (sideWidth * 2)))
            }

            // Right side - spinner when processing, placeholder otherwise
            if hasActivity {
                ProcessingSpinner()
                    .frame(width: sideWidth, alignment: .center)
            } else {
                Color.clear
                    .frame(width: sideWidth)
            }
        }
        .frame(height: viewModel.closedNotchSize.height)
    }

    private var sideWidth: CGFloat {
        // Fixed width for side elements (logo and spinner)
        28
    }

    // MARK: - Opened Header Content

    @ViewBuilder
    private var openedHeaderContent: some View {
        HStack(spacing: 8) {
            // Left Side: Navigation (Back Button)
            if case .chat(let session) = viewModel.contentType {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.exitChat()
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Sessions")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(.rect(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Center: Spacer deals with the physical notch
                Spacer(minLength: 160)

                // Right Side: Model Selector
                if session.isLive {
                    ModelSelectorButton(session: session)
                } else if let model = session.model {
                     Text(model.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .clipShape(.rect(cornerRadius: 6))
                }
            } else if case .sessions = viewModel.contentType {
                Spacer()

                // Settings button when showing sessions
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.showSettings()
                    }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            } else {
                Spacer()
            }
        }
        .padding(.leading, 4)
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        Group {
            switch viewModel.contentType {
            case .sessions:
                SessionsListView(viewModel: viewModel, sessionManager: viewModel.sessionManager)
            case .chat(let session):
                SessionChatView(session: session)
            case .settings:
                SettingsContentView(viewModel: viewModel)
            }
        }
        .frame(width: notchSize.width - 24)
    }

    // MARK: - Event Handlers

    private func handleStatusChange(from oldStatus: NotchStatus, to newStatus: NotchStatus) {
        switch newStatus {
        case .opened, .hint:
            isVisible = true
        case .closed:
            guard viewModel.hasPhysicalNotch else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if viewModel.status == .closed && !hasActivity && viewModel.unreadSession == nil {
                    isVisible = false
                }
            }
        }
    }

    private func handleSessionsChange(_ sessions: [ManagedSession]) {
        if sessions.contains(where: { $0.phase == .thinking || $0.phase == .executing }) {
            isVisible = true
        }
    }
}

// MARK: - Processing Spinner

struct ProcessingSpinner: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
            .onAppear { isAnimating = true }
    }
}

// MARK: - Sessions List View

// MARK: - Settings Content View

struct SettingsContentView: View {
    @ObservedObject var viewModel: NotchViewModel
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showInDock") private var showInDock = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button(action: { viewModel.exitSettings() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 12, weight: .medium)) // Increased from 11
                    }
                    .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Settings")
                    .font(.system(size: 13, weight: .semibold)) // Increased from 12
                    .foregroundStyle(.white)

                Spacer()

                // Spacer for symmetry
                Color.clear.frame(width: 44)
            }

            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.top, 8)

            // Settings options
            VStack(spacing: 2) {
                SettingsToggleRow(
                    title: "Launch at Login",
                    subtitle: "Start Pi Island when you log in",
                    icon: "power",
                    isOn: $launchAtLogin
                )
                .onChange(of: launchAtLogin) { _, newValue in
                    setLaunchAtLogin(enabled: newValue)
                }

                SettingsToggleRow(
                    title: "Show in Dock",
                    subtitle: "Display app icon in the Dock",
                    icon: "dock.rectangle",
                    isOn: $showInDock
                )
                .onChange(of: showInDock) { _, newValue in
                    setShowInDock(enabled: newValue)
                }
            }
            .padding(.vertical, 8)

            Spacer()

            // Version info
            Text("Pi Island v0.1.0")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.bottom, 8)
        }
        .padding(.top, 8)
    }

    private func setLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
        }
    }

    private func setShowInDock(enabled: Bool) {
        if enabled {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - Settings Toggle Row

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .scaleEffect(0.8)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Sessions List View

struct SessionsListView: View {
    @ObservedObject var viewModel: NotchViewModel
    @Bindable var sessionManager: SessionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Sessions")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Text("\(sessionManager.liveSessions.count) active")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 16)

            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.horizontal, 16)

            // Normal scroll - sessions at top
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    // Live sessions first (at top)
                    ForEach(sessionManager.liveSessions) { session in
                        SessionRowView(session: session, isSelected: session.id == sessionManager.selectedSessionId)
                            .padding(.horizontal, 16)
                            .onTapGesture {
                                viewModel.showChat(for: session)
                            }
                    }

                    // Historical sessions
                    if !sessionManager.historicalSessions.isEmpty {
                        Text("Recent")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        ForEach(sessionManager.historicalSessions.prefix(5)) { session in
                            SessionRowView(session: session, isSelected: false)
                                .padding(.horizontal, 16)
                                .onTapGesture {
                                    resumeHistoricalSession(session)
                                }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            // Refresh session list when view appears
            sessionManager.refreshSessions()
        }
    }

    private func resumeHistoricalSession(_ session: ManagedSession) {
        // print("[DEBUG] resumeHistoricalSession: \(session.projectName), messages: \(session.messages.count)")

        // Immediately show the session (provides instant feedback)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            viewModel.showChat(for: session)
        }

        // Resume in background - the session will update to live state
        Task {
            // print("[DEBUG] Starting resume task...")
            _ = await sessionManager.resumeSession(session)
            // print("[DEBUG] Resume complete: \(resumed?.projectName ?? "nil"), messages: \(resumed?.messages.count ?? 0)")
        }
    }
}

// MARK: - Session Row View

struct SessionRowView: View {
    @Bindable var session: ManagedSession
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) { // Increased spacing
            // Status indicator
            Circle()
                .fill(phaseColor)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.projectName)
                    .font(.system(size: 13, weight: .medium)) // Increased from 11
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let model = session.model {
                    Text(model.name ?? model.id)
                        .font(.system(size: 11)) // Increased from 9
                        .foregroundStyle(.white.opacity(0.5))
                } else if !session.isLive {
                    Text(formatDate(session.lastActivity))
                        .font(.system(size: 11)) // Increased from 9
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11)) // Increased from 10
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 12) // Increased padding
        .padding(.vertical, 10)   // Increased padding
        .background(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.06)) // Slightly lighter backgrounds
        .clipShape(.rect(cornerRadius: 10)) // Smoother corners
    }

    private var phaseColor: Color {
        // Check for externally thinking sessions first (terminal pi)
        if session.isLikelyThinking {
            return .blue  // Thinking
        }

        // Check for externally active sessions
        if session.isLikelyExternallyActive {
            return .yellow
        }

        switch session.phase {
        case .disconnected: return .gray
        case .starting: return .orange
        case .idle: return .green
        case .thinking: return .blue
        case .executing: return .cyan
        case .error: return .red
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
