//
//  NotchView.swift
//  PiIsland
//
//  The main dynamic island SwiftUI view
//

import SwiftUI

// Corner radius constants
private let cornerRadiusInsets = (
    opened: (top: CGFloat(19), bottom: CGFloat(24)),
    closed: (top: CGFloat(6), bottom: CGFloat(14))
)

struct NotchView: View {
    let viewModel: NotchViewModel
    @State private var isVisible: Bool = false
    @State private var isHovering: Bool = false
    @State private var shouldBounceLogo: Bool = false

    // MARK: - Sizing

    /// Extra width for expanding when there's activity (like Dynamic Island)
    private var expansionWidth: CGFloat {
        guard hasActivity else { return 0 }
        // Expand to make room for logo and indicator outside physical notch
        return 2 * sideWidth + 16
    }

    private var notchSize: CGSize {
        switch viewModel.status {
        case .closed, .hint:
            return CGSize(
                width: viewModel.closedNotchSize.width + expansionWidth,
                height: viewModel.closedNotchSize.height
            )
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
        case .opened: return openAnimation
        case .hint: return hintAnimation
        case .closed: return closeAnimation
        }
    }

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
                    .animation(animationForStatus, value: viewModel.status)
                    .animation(openAnimation, value: notchSize)
                    .animation(.smooth, value: hasActivity)
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
            if !viewModel.hasPhysicalNotch {
                isVisible = true
            }

            viewModel.onAgentCompletedForBounce = { [self] in
                triggerBounceAnimation()
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
            headerRow
                .frame(height: max(24, viewModel.closedNotchSize.height))

            if viewModel.status == .opened {
                contentView
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

    /// Current activity state from SessionManager (reactive, no polling)
    private var activityState: SessionManager.ActivityState {
        viewModel.sessionManager.activityState
    }

    private var hasActivity: Bool {
        activityState != .idle
    }

    private func activityColor(for state: SessionManager.ActivityState) -> Color {
        switch state {
        case .idle: return .gray
        case .thinking: return .blue
        case .executing: return .cyan
        case .externallyActive: return .yellow
        case .error: return .red
        }
    }

    private var isHintState: Bool {
        viewModel.status == .hint
    }

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 0) {
            // Left side - Pi logo
            HStack(spacing: 4) {
                PiLogo(
                    size: 14,
                    isAnimating: activityState.shouldAnimate,
                    isPulsing: isHintState,
                    bounce: shouldBounceLogo,
                    color: activityColor(for: activityState)
                )
            }
            .frame(width: viewModel.status == .opened ? nil : sideWidth)

            // Center content
            if viewModel.status == .opened {
                openedHeaderContent
            } else if !hasActivity {
                Rectangle()
                    .fill(.clear)
                    .frame(width: viewModel.closedNotchSize.width - 20)
            } else {
                Rectangle()
                    .fill(.black)
                    .frame(width: viewModel.closedNotchSize.width - cornerRadiusInsets.closed.top)
            }

            // Right side - symmetry spacer when closed with activity
            if hasActivity && viewModel.status != .opened {
                Color.clear
                    .frame(width: sideWidth)
            }
        }
        .frame(height: viewModel.closedNotchSize.height)
    }

    /// Fixed width for side elements (logo area)
    private var sideWidth: CGFloat { 28 }

    // MARK: - Opened Header Content

    private var isChatView: Bool {
        if case .chat = viewModel.contentType { return true }
        return false
    }

    private var isUsageView: Bool {
        if case .usage = viewModel.contentType { return true }
        return false
    }

    @ViewBuilder
    private var openedHeaderContent: some View {
        HStack(spacing: 8) {
            // Left Side: Navigation back button
            if case .chat = viewModel.contentType {
                NotchBackButton(title: "Sessions") {
                    viewModel.exitChat()
                }
            } else if case .settings = viewModel.contentType {
                NotchBackButton(title: "Sessions") {
                    viewModel.exitSettings()
                }
            }

            Spacer(minLength: isChatView ? 160 : 0)

            // Session/Usage toggle button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if case .usage = viewModel.contentType {
                        viewModel.exitUsage()
                    } else {
                        viewModel.showUsage()
                    }
                }
            } label: {
                Image(systemName: isUsageView ? "list.bullet" : "chart.bar.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(isUsageView ? .white : .white.opacity(0.5))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(isUsageView ? 0.15 : 0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help(isUsageView ? "Sessions" : "Usage Monitor")

            // Settings button
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
            .help("Settings")
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
                SettingsContentView()
            case .usage:
                UsageNotchView()
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
            Task {
                try? await Task.sleep(for: .milliseconds(350))
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

    private func triggerBounceAnimation() {
        isVisible = true
        shouldBounceLogo = true

        Task {
            try? await Task.sleep(for: .milliseconds(600))
            shouldBounceLogo = false
        }
    }
}

// MARK: - Back Button

private struct NotchBackButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                action()
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
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
    }
}
