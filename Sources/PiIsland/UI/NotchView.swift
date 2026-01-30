//
//  NotchView.swift
//  PiIsland
//
//  The main dynamic island SwiftUI view
//

import SwiftUI
import ServiceManagement

// Corner radius constants
private let cornerRadiusInsets = (
    opened: (top: CGFloat(19), bottom: CGFloat(24)),
    closed: (top: CGFloat(6), bottom: CGFloat(14))
)

struct NotchView: View {
    @ObservedObject var viewModel: NotchViewModel
    @State private var isVisible: Bool = false
    @State private var isHovering: Bool = false

    // MARK: - Sizing

    private var notchSize: CGSize {
        switch viewModel.status {
        case .closed, .popping:
            return viewModel.closedNotchSize
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

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
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
                    .animation(viewModel.status == .opened ? openAnimation : closeAnimation, value: viewModel.status)
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
    }

    // MARK: - Notch Layout

    @ViewBuilder
    private var notchLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row - always present
            headerRow
                .frame(height: max(24, viewModel.closedNotchSize.height))

            // Content only when opened
            if viewModel.status == .opened {
                contentView
                    .frame(width: notchSize.width - 24)
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
        viewModel.sessionManager.liveSessions.contains { session in
            session.phase == .thinking || session.phase == .executing
        }
    }

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 0) {
            // Left side - Pi logo
            HStack(spacing: 4) {
                PiLogo(size: 14, isAnimating: hasActivity)
            }
            .frame(width: viewModel.status == .opened ? nil : sideWidth)
            .padding(.leading, viewModel.status == .opened ? 8 : 0)

            // Center
            if viewModel.status == .opened {
                openedHeaderContent
            } else {
                // Closed: black spacer
                Rectangle()
                    .fill(.black)
                    .frame(width: viewModel.closedNotchSize.width - cornerRadiusInsets.closed.top)
            }

            // Right side - spinner when processing
            if hasActivity {
                ProcessingSpinner()
                    .frame(width: viewModel.status == .opened ? 20 : sideWidth)
            }
        }
        .frame(height: viewModel.closedNotchSize.height)
    }

    private var sideWidth: CGFloat {
        max(0, viewModel.closedNotchSize.height - 12) + 10
    }

    // MARK: - Opened Header Content

    @ViewBuilder
    private var openedHeaderContent: some View {
        HStack(spacing: 8) {
            // Back button when in chat or settings
            if case .chat = viewModel.contentType {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.exitChat()
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Sessions")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(.rect(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Settings button when showing sessions
            if case .sessions = viewModel.contentType {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.showSettings()
                    }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }

            // Model badge when in chat
            if case .chat(let session) = viewModel.contentType,
               let model = session.model {
                Text(model.name ?? model.id)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
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
        case .opened, .popping:
            isVisible = true
        case .closed:
            guard viewModel.hasPhysicalNotch else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if viewModel.status == .closed && !hasActivity {
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
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Settings")
                    .font(.system(size: 12, weight: .semibold))
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Text("\(sessionManager.liveSessions.count) active")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Divider()
                .background(Color.white.opacity(0.1))

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    // Live sessions
                    ForEach(sessionManager.liveSessions) { session in
                        SessionRowView(session: session, isSelected: session.id == sessionManager.selectedSessionId)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    viewModel.showChat(for: session)
                                }
                            }
                    }

                    // Historical sessions
                    if !sessionManager.historicalSessions.isEmpty {
                        Text("Recent")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)

                        ForEach(sessionManager.historicalSessions.prefix(5)) { session in
                            SessionRowView(session: session, isSelected: false)
                                .onTapGesture {
                                    resumeHistoricalSession(session)
                                }
                        }
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private func resumeHistoricalSession(_ session: ManagedSession) {
        Task {
            // Resume the session and wait for it to be live
            if let resumed = await sessionManager.resumeSession(session) {
                await MainActor.run {
                    // Show the live, interactive session
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.showChat(for: resumed)
                    }
                }
            }
        }
    }
}

// MARK: - Session Row View

struct SessionRowView: View {
    let session: ManagedSession
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(phaseColor)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.projectName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let model = session.model {
                    Text(model.name ?? model.id)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                } else if !session.isLive {
                    Text(formatDate(session.lastActivity))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
        .clipShape(.rect(cornerRadius: 8))
    }

    private var phaseColor: Color {
        // Check for externally active sessions first
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
