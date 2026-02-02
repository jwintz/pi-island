import MarkdownUI
import SwiftUI

// MARK: - SessionChatView

/// Chat view for a managed session
struct SessionChatView: View {
    @Bindable var session: ManagedSession
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        // let _ = print("[DEBUG] SessionChatView rendering: \(session.projectName), messages: \(session.messages.count), isLive: \(session.isLive), phase: \(session.phase)")

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
                    // Instant scroll to bottom (no animation)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
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

            // Model selector (live) or model badge (historical)
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

            // Thinking level badge (only for models that support reasoning)
            if session.isLive, session.model?.reasoning == true {
                Text(session.thinkingLevel.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(.rect(cornerRadius: 6))
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
        text.count > 500 || text.components(separatedBy: "\n").count > 10
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                Circle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 6, height: 6)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 0) {
                    // Always use Markdown for syntax highlighting
                    Markdown(isExpanded || !isLong ? text : truncatedText)
                        .markdownTheme(.piIsland)
                }

                Spacer(minLength: 40)
            }

            if isLong {
                Button(action: { withAnimation { isExpanded.toggle() } }) {
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

    private var truncatedText: String {
        let lines = text.components(separatedBy: "\n")
        let maxLines = 8

        if lines.count <= maxLines {
            return text
        }

        var result = Array(lines.prefix(maxLines))

        // Check if we're cutting inside a code block
        var inCodeBlock = false
        for line in result {
            if line.hasPrefix("```") {
                inCodeBlock.toggle()
            }
        }

        // Close unclosed code block
        if inCodeBlock {
            result.append("```")
        }

        result.append("...")

        return result.joined(separator: "\n")
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
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Tool Result View

private struct ToolResultView: View {
    let result: String
    let toolName: String
    @State private var isFullyExpanded = false

    private var lines: [String] {
        result.components(separatedBy: "\n")
    }

    private var collapsedLineCount: Int { 12 }

    private var displayLines: [String] {
        if isFullyExpanded {
            return lines
        } else {
            return Array(lines.prefix(collapsedLineCount))
        }
    }

    private var language: String {
        // Detect language from tool name or content
        switch toolName.lowercased() {
        case "read":
            return detectLanguageFromContent()
        case "bash":
            return "bash"
        default:
            return "text"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with language and copy button
            HStack {
                Text(language)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Button(action: copyResult) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.08))

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    // Line numbers
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(Array(displayLines.enumerated()), id: \.offset) { index, _ in
                            Text("\(index + 1)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.25))
                                .frame(height: 15)
                        }
                    }
                    .padding(.trailing, 8)
                    .padding(.leading, 8)

                    Divider()
                        .frame(width: 1)
                        .background(Color.white.opacity(0.1))

                    // Code lines with highlighting
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(displayLines.enumerated()), id: \.offset) { _, line in
                            highlightedLine(line)
                                .frame(height: 15, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.vertical, 6)
            }

            // Expand/collapse button
            if lines.count > collapsedLineCount {
                Button(action: { withAnimation { isFullyExpanded.toggle() } }) {
                    HStack(spacing: 4) {
                        Text(isFullyExpanded ? "Show less" : "Show all \(lines.count) lines")
                            .font(.system(size: 9, design: .monospaced))
                        Image(systemName: isFullyExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundStyle(.blue.opacity(0.7))
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .background(Color.white.opacity(0.05))
            }
        }
        .background(Color.black.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func copyResult() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
    }

    @ViewBuilder
    private func highlightedLine(_ line: String) -> some View {
        Text(attributedLine(line))
            .font(.system(size: 10, design: .monospaced))
    }

    private func attributedLine(_ line: String) -> AttributedString {
        var result = AttributedString(line.isEmpty ? " " : line)

        // Check for error lines first
        if isErrorLine(line) {
            result.foregroundColor = .red.opacity(0.8)
            return result
        }

        result.foregroundColor = .white.opacity(0.7)

        // Apply syntax highlighting based on detected language
        applyHighlighting(to: &result, line: line)

        return result
    }

    private func applyHighlighting(to result: inout AttributedString, line: String) {
        let lang = language.lowercased()

        switch lang {
        case "swift":
            highlightSwift(in: &result, line: line)
        case "json":
            highlightJSON(in: &result, line: line)
        case "bash", "shell", "sh":
            highlightBash(in: &result, line: line)
        case "python", "py":
            highlightPython(in: &result, line: line)
        default:
            highlightGeneric(in: &result, line: line)
        }
    }

    private func highlightSwift(in result: inout AttributedString, line: String) {
        let keywords = ["func", "var", "let", "if", "else", "guard", "return", "import", "struct", "class", "enum", "protocol", "extension", "private", "public", "static", "override", "async", "await", "try", "catch", "for", "while", "switch", "case", "default", "break", "continue", "self", "nil", "true", "false", "@State", "@Binding", "@Observable", "@MainActor", "some", "any", "init"]
        let types = ["String", "Int", "Bool", "Double", "Array", "Dictionary", "View", "Text", "VStack", "HStack", "Button", "Color"]

        for kw in keywords {
            highlightPattern(in: &result, line: line, pattern: "\\b\(kw)\\b", color: .pink.opacity(0.9))
        }
        for t in types {
            highlightPattern(in: &result, line: line, pattern: "\\b\(t)\\b", color: .cyan.opacity(0.9))
        }
        highlightPattern(in: &result, line: line, pattern: "\"[^\"]*\"", color: .green.opacity(0.9))
        highlightPattern(in: &result, line: line, pattern: "\\b\\d+(\\.\\d+)?\\b", color: .orange.opacity(0.9))
        highlightPattern(in: &result, line: line, pattern: "//.*$", color: .white.opacity(0.4))
    }

    private func highlightJSON(in result: inout AttributedString, line: String) {
        // JSON keys (quoted strings followed by colon)
        highlightPattern(in: &result, line: line, pattern: "\"[^\"]+\"\\s*:", color: .cyan.opacity(0.9))
        // JSON string values
        highlightPattern(in: &result, line: line, pattern: ":\\s*\"[^\"]*\"", color: .green.opacity(0.9))
        // Numbers
        highlightPattern(in: &result, line: line, pattern: ":\\s*\\d+(\\.\\d+)?", color: .orange.opacity(0.9))
        // Booleans and null
        highlightPattern(in: &result, line: line, pattern: "\\b(true|false|null)\\b", color: .pink.opacity(0.9))
    }

    private func highlightBash(in result: inout AttributedString, line: String) {
        let keywords = ["if", "then", "else", "fi", "for", "do", "done", "while", "case", "esac", "function", "return", "exit", "export", "local", "echo", "cd", "ls", "rm", "cp", "mv", "mkdir", "cat", "grep", "sed", "awk", "find"]
        for kw in keywords {
            highlightPattern(in: &result, line: line, pattern: "\\b\(kw)\\b", color: .pink.opacity(0.9))
        }
        highlightPattern(in: &result, line: line, pattern: "\"[^\"]*\"", color: .green.opacity(0.9))
        highlightPattern(in: &result, line: line, pattern: "'[^']*'", color: .green.opacity(0.9))
        highlightPattern(in: &result, line: line, pattern: "\\$\\w+", color: .cyan.opacity(0.9))
        highlightPattern(in: &result, line: line, pattern: "#.*$", color: .white.opacity(0.4))
    }

    private func highlightPython(in result: inout AttributedString, line: String) {
        let keywords = ["def", "class", "if", "elif", "else", "for", "while", "return", "import", "from", "as", "try", "except", "with", "lambda", "yield", "raise", "pass", "break", "continue", "and", "or", "not", "in", "is", "None", "True", "False", "self", "async", "await"]
        for kw in keywords {
            highlightPattern(in: &result, line: line, pattern: "\\b\(kw)\\b", color: .pink.opacity(0.9))
        }
        highlightPattern(in: &result, line: line, pattern: "\"[^\"]*\"", color: .green.opacity(0.9))
        highlightPattern(in: &result, line: line, pattern: "'[^']*'", color: .green.opacity(0.9))
        highlightPattern(in: &result, line: line, pattern: "\\b\\d+(\\.\\d+)?\\b", color: .orange.opacity(0.9))
        highlightPattern(in: &result, line: line, pattern: "#.*$", color: .white.opacity(0.4))
    }

    private func highlightGeneric(in result: inout AttributedString, line: String) {
        highlightPattern(in: &result, line: line, pattern: "\"[^\"]*\"", color: .green.opacity(0.9))
        highlightPattern(in: &result, line: line, pattern: "\\b\\d+(\\.\\d+)?\\b", color: .orange.opacity(0.9))
    }

    private func highlightPattern(in result: inout AttributedString, line: String, pattern: String, color: Color) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let range = NSRange(line.startIndex..., in: line)
        let matches = regex.matches(in: line, options: [], range: range)

        for match in matches {
            guard let swiftRange = Range(match.range, in: line) else { continue }
            let startOffset = line.distance(from: line.startIndex, to: swiftRange.lowerBound)
            let endOffset = line.distance(from: line.startIndex, to: swiftRange.upperBound)

            let attrStart = result.index(result.startIndex, offsetByCharacters: startOffset)
            let attrEnd = result.index(result.startIndex, offsetByCharacters: endOffset)

            if attrStart < attrEnd {
                result[attrStart..<attrEnd].foregroundColor = color
            }
        }
    }

    private func detectLanguageFromContent() -> String {
        let firstLine = lines.first ?? ""
        let content = result.lowercased()

        // Check for JSON
        if firstLine.trimmingCharacters(in: .whitespaces).hasPrefix("{") ||
           firstLine.trimmingCharacters(in: .whitespaces).hasPrefix("[") {
            return "json"
        }
        // Check for Swift
        if content.contains("import ") || content.contains("func ") || content.contains("struct ") || content.contains("class ") {
            return "swift"
        }
        // Check for Python
        if content.contains("def ") || content.contains("import ") && content.contains(":") {
            return "python"
        }
        return "text"
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

            Markdown(text)
                .markdownTheme(.piIsland)

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
                Text(session.model?.displayName ?? "Select Model")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08))
        .clipShape(.rect(cornerRadius: 6))
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
