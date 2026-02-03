import MarkdownUI
import OSLog
import SwiftUI
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "com.pi-island", category: "ChatView")

// MARK: - SessionChatView

/// Chat view for a managed session
struct SessionChatView: View {
    @Bindable var session: ManagedSession
    @State private var inputText = ""
    @State private var showCommandCompletion = false
    @State private var showFileCompletion = false
    @State private var selectedCommandIndex = 0
    @State private var selectedFileIndex = 0
    @State private var fileCompletions: [FileCompletionInfo] = []
    @State private var fileCompletionQuery = ""
    @FocusState private var isInputFocused: Bool

    /// Filtered commands based on input
    private var filteredCommands: [SlashCommandInfo] {
        guard inputText.hasPrefix("/") else { return [] }
        let query = String(inputText.dropFirst()).lowercased()
        if query.isEmpty {
            return session.availableCommands
        }
        return session.availableCommands.filter {
            $0.displayName.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            chatHeader

            // Messages - inverted scroll, newest at bottom
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        // Anchor at top (visual bottom due to inversion)
                        Color.clear.frame(height: 1).id("bottom")

                        // Command output (from extension commands) - show at visual bottom
                        if let output = session.commandOutput {
                            CommandOutputView(text: output)
                                .scaleEffect(x: 1, y: -1)
                        }

                        // Current tool execution
                        if let tool = session.currentTool {
                            ToolExecutionView(tool: tool)
                                .scaleEffect(x: 1, y: -1)
                        }

                        // Streaming text
                        if !session.streamingText.isEmpty {
                            StreamingMessageView(text: session.streamingText)
                                .scaleEffect(x: 1, y: -1)
                        }

                        // Streaming thinking
                        if !session.streamingThinking.isEmpty {
                            ThinkingMessageView(text: session.streamingThinking)
                                .scaleEffect(x: 1, y: -1)
                        }

                        // Messages in reverse order (oldest first in array, appear at bottom)
                        ForEach(session.messages.filter(\.isDisplayable).reversed()) { message in
                            MessageRow(message: message)
                                .scaleEffect(x: 1, y: -1)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .scaleEffect(x: 1, y: -1)
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
                .onChange(of: session.commandOutput) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Input bar (only for live sessions)
            if session.isLive {
                VStack(spacing: 0) {
                    // Command completion popover
                    if showCommandCompletion && !filteredCommands.isEmpty {
                        commandCompletionView
                    }
                    // File completion popover
                    if showFileCompletion && !fileCompletions.isEmpty {
                        fileCompletionView
                    }
                    inputBar
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: inputText) { _, newValue in
            // Show command completion when typing /
            let shouldShowCommand = newValue.hasPrefix("/") && !filteredCommands.isEmpty
            showCommandCompletion = shouldShowCommand
            selectedCommandIndex = 0

            // Check for @ file reference trigger
            updateFileCompletion(for: newValue)
        }
        .onAppear {
            logger.info("ChatView appeared, availableCommands: \(self.session.availableCommands.count)")
            // Fetch stats when chat view appears
            Task { await session.refreshStats() }
        }
    }

    private var chatHeader: some View {
        HStack(spacing: 12) {
            // Status indicator (replaces chevron)
            Circle()
                .fill(phaseColor)
                .frame(width: 8, height: 8)

            Text(session.projectName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)

            Spacer()

            // Token/cost display
            if let stats = session.sessionStats {
                HStack(spacing: 8) {
                    // Tokens
                    HStack(spacing: 3) {
                        Image(systemName: "text.word.spacing")
                            .font(.system(size: 9))
                        Text(stats.formattedTokens)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(.white.opacity(0.5))

                    // Cost
                    Text(stats.formattedCost)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.green.opacity(0.7))
                }
            }
        }
        .padding(.vertical, 12)
    }

    private var commandCompletionView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(filteredCommands.prefix(8).enumerated()), id: \.element.id) { index, cmd in
                    CommandCompletionRow(
                        command: cmd,
                        isSelected: index == selectedCommandIndex
                    )
                    .onTapGesture {
                        selectCommand(cmd)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 200)
        .background(Color.black.opacity(0.9))
        .clipShape(.rect(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var fileCompletionView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(fileCompletions.prefix(10).enumerated()), id: \.element.id) { index, file in
                    FileCompletionRow(
                        file: file,
                        isSelected: index == selectedFileIndex
                    )
                    .onTapGesture {
                        selectFile(file)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 250)
        .background(Color.black.opacity(0.9))
        .clipShape(.rect(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
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
                    if showCommandCompletion && !filteredCommands.isEmpty {
                        selectCommand(filteredCommands[selectedCommandIndex])
                    } else if showFileCompletion && !fileCompletions.isEmpty {
                        selectFile(fileCompletions[selectedFileIndex])
                    } else {
                        sendMessage()
                    }
                }
                .onKeyPress(.upArrow) {
                    if showCommandCompletion {
                        selectedCommandIndex = max(0, selectedCommandIndex - 1)
                        return .handled
                    }
                    if showFileCompletion {
                        selectedFileIndex = max(0, selectedFileIndex - 1)
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.downArrow) {
                    if showCommandCompletion {
                        selectedCommandIndex = min(filteredCommands.count - 1, selectedCommandIndex + 1)
                        return .handled
                    }
                    if showFileCompletion {
                        selectedFileIndex = min(fileCompletions.count - 1, selectedFileIndex + 1)
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.tab) {
                    if showCommandCompletion && !filteredCommands.isEmpty {
                        selectCommand(filteredCommands[selectedCommandIndex])
                        return .handled
                    }
                    if showFileCompletion && !fileCompletions.isEmpty {
                        selectFile(fileCompletions[selectedFileIndex])
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.escape) {
                    if showCommandCompletion {
                        showCommandCompletion = false
                        return .handled
                    }
                    if showFileCompletion {
                        showFileCompletion = false
                        return .handled
                    }
                    return .ignored
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
        // Check for externally thinking sessions first (terminal pi)
        if !session.isLive && session.isLikelyThinking {
            return .blue
        }

        // Check for externally active sessions
        if !session.isLive && session.isLikelyExternallyActive {
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

    private func selectCommand(_ command: SlashCommandInfo) {
        // Insert command with leading slash
        // Command names from Pi don't have leading slash, so we add it
        inputText = "/" + command.name + " "
        showCommandCompletion = false
    }

    private func selectFile(_ file: FileCompletionInfo) {
        // Find the @ position and replace the partial path
        if let atRange = findCurrentAtReference() {
            let before = String(inputText[inputText.startIndex..<atRange.lowerBound])
            let after = String(inputText[atRange.upperBound...])

            // If it's a directory, append / to allow further navigation
            if file.isDirectory {
                inputText = before + "@" + file.path + "/" + after
                // Refresh completions for the directory
                updateFileCompletion(for: inputText)
            } else {
                inputText = before + "@" + file.path + " " + after
                showFileCompletion = false
            }
        }
    }

    private func findCurrentAtReference() -> Range<String.Index>? {
        // Find the @ that starts the current file reference
        // Look backwards from cursor (end of string for now) to find @
        guard let atIndex = inputText.lastIndex(of: "@") else { return nil }
        return atIndex..<inputText.endIndex
    }

    private func updateFileCompletion(for text: String) {
        // Find @ followed by partial path
        guard let atIndex = text.lastIndex(of: "@") else {
            showFileCompletion = false
            return
        }

        let afterAt = String(text[text.index(after: atIndex)...])

        // Don't show completion if there's a space after the path (reference is complete)
        if afterAt.contains(" ") && !afterAt.hasSuffix("/") {
            showFileCompletion = false
            return
        }

        fileCompletionQuery = afterAt.trimmingCharacters(in: .whitespaces)
        selectedFileIndex = 0

        // Get the working directory from session
        let cwd = session.workingDirectory

        Task {
            let completions = await getFileCompletions(query: fileCompletionQuery, cwd: cwd)
            await MainActor.run {
                fileCompletions = completions
                showFileCompletion = !completions.isEmpty
            }
        }
    }

    private func getFileCompletions(query: String, cwd: String) async -> [FileCompletionInfo] {
        // Parse the query to get directory and file prefix
        let queryPath = query.isEmpty ? "." : query

        // Determine base directory and filter prefix
        var searchDir: String
        var filterPrefix: String

        if queryPath.hasSuffix("/") {
            // User typed a complete directory path, list its contents
            searchDir = (cwd as NSString).appendingPathComponent(queryPath)
            filterPrefix = ""
        } else if queryPath.contains("/") {
            // User is typing in a subdirectory
            let dirPart = (queryPath as NSString).deletingLastPathComponent
            searchDir = (cwd as NSString).appendingPathComponent(dirPart)
            filterPrefix = (queryPath as NSString).lastPathComponent.lowercased()
        } else {
            // User is typing at the root level
            searchDir = cwd
            filterPrefix = queryPath.lowercased()
        }

        // List directory contents
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: searchDir) else {
            return []
        }

        // Filter and sort
        var results: [FileCompletionInfo] = []
        let basePath = queryPath.contains("/")
            ? (queryPath as NSString).deletingLastPathComponent
            : ""

        for item in contents {
            // Skip hidden files unless user typed a dot
            if item.hasPrefix(".") && !filterPrefix.hasPrefix(".") {
                continue
            }

            // Filter by prefix
            if !filterPrefix.isEmpty && !item.lowercased().hasPrefix(filterPrefix) {
                continue
            }

            let fullPath = (searchDir as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)

            let relativePath = basePath.isEmpty ? item : (basePath as NSString).appendingPathComponent(item)

            results.append(FileCompletionInfo(
                path: relativePath,
                fullPath: fullPath,
                isDirectory: isDir.boolValue
            ))
        }

        // Sort: directories first, then alphabetically
        results.sort { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory
            }
            return a.path.localizedCaseInsensitiveCompare(b.path) == .orderedAscending
        }

        return Array(results.prefix(50))
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        showCommandCompletion = false
        showFileCompletion = false

        Task {
            // All messages go through sendPrompt (Pi handles slash commands internally)
            await session.sendPrompt(text)
        }
    }
}

// MARK: - Command Completion Row

private struct CommandCompletionRow: View {
    let command: SlashCommandInfo
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("/" + command.displayName)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)

            if let desc = command.description {
                Text(desc)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.blue.opacity(0.3) : Color.clear)
        .clipShape(.rect(cornerRadius: 4))
    }
}

// MARK: - File Completion Info

struct FileCompletionInfo: Identifiable, Equatable {
    let id = UUID()
    let path: String      // Relative path from cwd
    let fullPath: String  // Absolute path
    let isDirectory: Bool

    var displayName: String {
        if isDirectory {
            return path + "/"
        }
        return path
    }

    var iconName: String {
        if isDirectory {
            return "folder.fill"
        }
        // File type detection by extension
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "ts", "tsx", "js", "jsx": return "doc.text"
        case "json": return "curlybraces"
        case "md", "markdown": return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "webp": return "photo"
        case "yml", "yaml": return "list.bullet"
        default: return "doc"
        }
    }
}

// MARK: - File Completion Row

private struct FileCompletionRow: View {
    let file: FileCompletionInfo
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: file.iconName)
                .font(.system(size: 10))
                .foregroundStyle(file.isDirectory ? .yellow : .white.opacity(0.7))
                .frame(width: 14)

            Text(file.displayName)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.blue.opacity(0.3) : Color.clear)
        .clipShape(.rect(cornerRadius: 4))
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
        HStack(alignment: .top, spacing: 6) {
            Spacer(minLength: 40)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.6))
                .clipShape(.rect(cornerRadius: 12))
            Circle()
                .fill(Color.blue)
                .frame(width: 6, height: 6)
                .padding(.top, 5)
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
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 0) {
                    // Always use Markdown for syntax highlighting
                    Markdown(isExpanded || !isLong ? text : truncatedText)
                        .markdownTheme(.piIslandMonospaced)
                }

                Spacer(minLength: 40)
            }

            if isLong {
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Show less" : "Show more")
                            .font(.system(size: 10, design: .monospaced))
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
                .padding(.top, 5)
                .opacity(0.8)

            Markdown(text)
                .markdownTheme(.piIslandMonospaced)

            // Cursor
            Rectangle()
                .fill(Color.white.opacity(0.7))
                .frame(width: 2, height: 14)
                .padding(.top, 2)

            Spacer(minLength: 40)
        }
    }
}

// MARK: - Command Output View

private struct CommandOutputView: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // System indicator
            Image(systemName: "terminal")
                .font(.system(size: 12))
                .foregroundStyle(.green)
                .padding(.top, 3)

            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.green)
                .textSelection(.enabled)

            Spacer(minLength: 20)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
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
        if let path = tool.args["path"]?.stringValue {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        if let command = tool.args["command"]?.stringValue {
            return String(command.prefix(50))
        }
        return ""
    }
}

// MARK: - MessageRow
