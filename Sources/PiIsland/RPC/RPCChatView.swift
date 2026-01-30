import SwiftUI

// MARK: - SessionChatView

/// Chat view for a managed session
struct SessionChatView: View {
    @Bindable var session: ManagedSession
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()
                .background(Color.white.opacity(0.1))

            // Messages
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(session.messages) { message in
                            MessageRow(message: message)
                        }

                        // Streaming thinking
                        if !session.streamingThinking.isEmpty {
                            ThinkingMessageView(text: session.streamingThinking)
                        }

                        // Streaming text
                        if !session.streamingText.isEmpty {
                            StreamingMessageView(text: session.streamingText)
                        }

                        // Current tool execution
                        if let tool = session.currentTool {
                            ToolExecutionView(tool: tool)
                        }

                        // Scroll anchor
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .onAppear {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: session.messages.count) {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: session.streamingText) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: session.streamingThinking) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }

            // Input bar (only for live sessions)
            if session.isLive {
                inputBar
            }
        }
    }

    private var headerView: some View {
        HStack(spacing: 8) {
            // Status indicator
            Circle()
                .fill(phaseColor)
                .frame(width: 8, height: 8)

            // Project name
            Text(session.projectName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            // Model selector
            if session.isLive {
                ModelSelectorButton(session: session)
            } else if let model = session.model {
                Text(model.displayName)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 4))
            }

            // Thinking level badge (only for models that support reasoning)
            if session.isLive, session.model?.reasoning == true {
                Text(session.thinkingLevel.rawValue)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 4))
                    .onTapGesture {
                        Task { await session.cycleThinkingLevel() }
                    }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.1))
                .clipShape(.rect(cornerRadius: 8))
                .focused($isInputFocused)
                .onSubmit {
                    sendMessage()
                }
                .disabled(session.phase == .disconnected)

            if session.isStreaming {
                // Abort button
                Button(action: { Task { await session.abort() } }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            } else {
                // Send button
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(canSend ? .blue : .gray.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        session.phase != .disconnected &&
        !session.isStreaming
    }

    private var phaseColor: Color {
        switch session.phase {
        case .disconnected: return .gray
        case .starting: return .orange
        case .idle: return .green
        case .thinking: return .blue
        case .executing: return .cyan
        case .error: return .red
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        Task {
            await session.sendPrompt(text)
        }
    }
}

// MARK: - MessageRow

private struct MessageRow: View {
    let message: RPCMessage

    var body: some View {
        switch message.role {
        case .user:
            UserBubble(text: message.content ?? "")
        case .assistant:
            AssistantBubble(text: message.content ?? "")
        case .tool:
            ToolRow(message: message)
        }
    }
}

// MARK: - User Bubble

private struct UserBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.6))
                .clipShape(.rect(cornerRadius: 12))
        }
    }
}

// MARK: - Assistant Bubble

private struct AssistantBubble: View {
    let text: String
    @State private var isExpanded = false

    private var isLong: Bool {
        text.count > 300 || text.components(separatedBy: "\n").count > 6
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Circle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 6, height: 6)
                    .padding(.top, 4)

                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(isExpanded ? nil : 6)

                Spacer(minLength: 40)
            }

            if isLong {
                Button(action: { isExpanded.toggle() }) {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Show less" : "Show more")
                            .font(.system(size: 10))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundStyle(.blue.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
            }
        }
    }
}

// MARK: - Tool Row

private struct ToolRow: View {
    let message: RPCMessage
    @State private var isExpanded = false

    private var statusColor: Color {
        switch message.toolStatus {
        case .running: return .blue
        case .success: return .green
        case .error: return .red
        case nil: return .gray
        }
    }

    private var hasResult: Bool {
        message.toolResult != nil && message.toolStatus != .running
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                Text(message.toolName ?? "tool")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))

                Text(message.toolArgsPreview)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)

                Spacer()

                if hasResult {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if hasResult {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }
            }

            if isExpanded, let result = message.toolResult {
                ToolResultView(result: result, toolName: message.toolName ?? "")
                    .padding(.leading, 12)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Tool Result View

private struct ToolResultView: View {
    let result: String
    let toolName: String

    private var lines: [String] {
        result.components(separatedBy: "\n")
    }

    private var displayLines: [String] {
        Array(lines.prefix(12))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(displayLines.enumerated()), id: \.offset) { index, line in
                HStack(spacing: 0) {
                    if toolName == "read" || toolName == "bash" {
                        Text("\(index + 1)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.2))
                            .frame(width: 24, alignment: .trailing)
                            .padding(.trailing, 6)
                    }

                    Text(line.isEmpty ? " " : line)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(isErrorLine(line) ? .red.opacity(0.8) : .white.opacity(0.5))
                        .lineLimit(1)
                }
            }

            if lines.count > 12 {
                Text("... (\(lines.count - 12) more lines)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.top, 2)
            }
        }
        .padding(6)
        .background(Color.white.opacity(0.03))
        .clipShape(.rect(cornerRadius: 4))
    }

    private func isErrorLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return lowered.hasPrefix("error:") ||
               lowered.hasPrefix("fatal:") ||
               lowered.hasPrefix("warning:") ||
               lowered.contains("traceback")
    }
}

// MARK: - Streaming Message View

// MARK: - Thinking Message View

private struct ThinkingMessageView: View {
    let text: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header - tap to expand/collapse
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 10))
                        .foregroundStyle(.purple.opacity(0.8))

                    Text("Thinking...")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.purple.opacity(0.8))

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .buttonStyle(.plain)

            // Thinking content (collapsible)
            if isExpanded {
                Text(text)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.purple.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.purple.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Streaming Message View

private struct StreamingMessageView: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Pulsing indicator
            Circle()
                .fill(Color.blue)
                .frame(width: 6, height: 6)
                .padding(.top, 4)
                .opacity(0.8)

            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.9))

            // Cursor
            Rectangle()
                .fill(Color.white.opacity(0.7))
                .frame(width: 2, height: 14)
                .padding(.top, 2)

            Spacer(minLength: 40)
        }
    }
}

// MARK: - Tool Execution View

private struct ToolExecutionView: View {
    let tool: RPCToolExecution

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Pulsing indicator
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)

                Text(tool.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))

                Text(toolPreview)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)

                Spacer()

                ProgressView()
                    .scaleEffect(0.5)
            }

            // Partial output
            if let partial = tool.partialOutput, !partial.isEmpty {
                Text(partial.suffix(200))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(3)
                    .padding(.leading, 12)
            }
        }
    }

    private var toolPreview: String {
        if let path = tool.args["path"] as? String {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        if let command = tool.args["command"] as? String {
            return String(command.prefix(50))
        }
        return ""
    }
}

// MARK: - Model Selector

private struct ModelSelectorButton: View {
    @Bindable var session: ManagedSession

    var body: some View {
        Menu {
            ForEach(sortedProviders, id: \.self) { provider in
                Section(provider) {
                    ForEach(modelsForProvider(provider)) { model in
                        Button(action: { selectModel(model) }) {
                            HStack {
                                Text(model.displayName)
                                if isCurrentModel(model) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let model = session.model {
                    Text(model.displayName)
                } else {
                    Text("Select Model")
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .font(.system(size: 9))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.1))
            .clipShape(.rect(cornerRadius: 4))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var sortedProviders: [String] {
        session.modelsByProvider.keys.sorted()
    }

    private func modelsForProvider(_ provider: String) -> [RPCModel] {
        session.modelsByProvider[provider] ?? []
    }

    private func isCurrentModel(_ model: RPCModel) -> Bool {
        guard let current = session.model else { return false }
        return current.id == model.id && current.provider == model.provider
    }

    private func selectModel(_ model: RPCModel) {
        Task {
            await session.setModel(provider: model.provider, modelId: model.id)
        }
    }
}
