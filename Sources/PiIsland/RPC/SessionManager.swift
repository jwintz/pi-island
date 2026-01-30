import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pi-island", category: "SessionManager")

/// Manages multiple Pi RPC sessions
@MainActor
@Observable
class SessionManager {
    /// All sessions (live RPC + historical)
    private(set) var sessions: [String: ManagedSession] = [:]

    /// Currently selected session ID
    var selectedSessionId: String?

    /// The currently selected session
    var selectedSession: ManagedSession? {
        guard let id = selectedSessionId else { return nil }
        return sessions[id]
    }

    /// Live sessions (connected RPC processes)
    var liveSessions: [ManagedSession] {
        sessions.values
            .filter { $0.isLive }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    /// Historical sessions (from JSONL files)
    var historicalSessions: [ManagedSession] {
        sessions.values
            .filter { !$0.isLive }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    /// All sessions sorted by activity
    var allSessions: [ManagedSession] {
        sessions.values.sorted { $0.lastActivity > $1.lastActivity }
    }

    // MARK: - Session Lifecycle

    /// Create and start a new RPC session
    func createSession(
        workingDirectory: String,
        provider: String? = nil,
        model: String? = nil
    ) async -> ManagedSession {
        let session = ManagedSession(
            id: UUID().uuidString,
            workingDirectory: workingDirectory,
            isLive: true
        )

        sessions[session.id] = session

        // Start the RPC process
        await session.start(provider: provider, model: model)

        // Auto-select if first session
        if selectedSessionId == nil {
            selectedSessionId = session.id
        }

        logger.info("Created session \(session.id) for \(workingDirectory)")
        return session
    }

    /// Stop and remove a session
    func removeSession(_ id: String) async {
        guard let session = sessions[id] else { return }

        if session.isLive {
            await session.stop()
        }

        sessions.removeValue(forKey: id)

        if selectedSessionId == id {
            selectedSessionId = liveSessions.first?.id
        }

        logger.info("Removed session \(id)")
    }

    /// Resume a historical session by starting a new RPC process with the session file
    func resumeSession(_ session: ManagedSession) async -> ManagedSession? {
        logger.info("resumeSession called for session \(session.id), isLive=\(session.isLive), sessionFile=\(session.sessionFile ?? "nil")")

        guard !session.isLive, let sessionFile = session.sessionFile else {
            logger.warning("Cannot resume: session is already live or has no session file")
            return nil
        }

        // Remove the historical session since we're resuming it
        sessions.removeValue(forKey: session.id)

        // Create a new live session
        let newSession = ManagedSession(
            id: UUID().uuidString,
            workingDirectory: session.workingDirectory,
            isLive: true
        )

        // Copy messages from historical session
        newSession.messages = session.messages
        newSession.model = session.model
        newSession.lastActivity = Date()
        newSession.sessionFile = sessionFile

        sessions[newSession.id] = newSession

        // Start with the session file to resume
        logger.info("Starting new session with resumeSessionFile: \(sessionFile)")
        await newSession.start(resumeSessionFile: sessionFile)

        selectedSessionId = newSession.id

        logger.info("Resumed session from \(sessionFile), messages count: \(newSession.messages.count)")
        return newSession
    }

    /// Load historical sessions from JSONL files
    func loadHistoricalSessions() async {
        let sessionsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pi/agent/sessions")

        guard FileManager.default.fileExists(atPath: sessionsDir.path) else {
            logger.info("No sessions directory found")
            return
        }

        do {
            let projectDirs = try FileManager.default.contentsOfDirectory(
                at: sessionsDir,
                includingPropertiesForKeys: [.isDirectoryKey]
            )

            for projectDir in projectDirs {
                guard projectDir.hasDirectoryPath else { continue }

                let sessionFiles = try FileManager.default.contentsOfDirectory(
                    at: projectDir,
                    includingPropertiesForKeys: [.contentModificationDateKey]
                ).filter { $0.pathExtension == "jsonl" }

                // Load most recent sessions per project
                let sortedFiles = sessionFiles.sorted { a, b in
                    let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                    let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                    return dateA > dateB
                }

                for file in sortedFiles.prefix(3) {
                    if let session = await parseSessionFile(file) {
                        // Don't overwrite live sessions
                        if sessions[session.id] == nil {
                            sessions[session.id] = session
                        }
                    }
                }
            }

            logger.info("Loaded \(self.sessions.count) historical sessions")
        } catch {
            logger.error("Error loading sessions: \(error.localizedDescription)")
        }
    }

    // MARK: - JSONL Parsing

    private func parseSessionFile(_ url: URL) async -> ManagedSession? {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        // Extract session ID from filename (format: timestamp_uuid.jsonl)
        let filename = url.deletingPathExtension().lastPathComponent
        let sessionId = filename.components(separatedBy: "_").last ?? filename

        var projectPath = ""
        var messages: [RPCMessage] = []
        var model: RPCModel?
        var lastActivity = Date.distantPast

        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            // Parse timestamp (can be string or number)
            if let tsString = json["timestamp"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: tsString) {
                    if date > lastActivity {
                        lastActivity = date
                    }
                }
            } else if let ts = json["timestamp"] as? Double {
                let date = Date(timeIntervalSince1970: ts / 1000)
                if date > lastActivity {
                    lastActivity = date
                }
            }

            // Parse entry type
            guard let type = json["type"] as? String else { continue }

            switch type {
            case "session":
                // Get the actual working directory from session entry
                if let cwd = json["cwd"] as? String {
                    projectPath = cwd
                }

            case "model_change":
                if let modelId = json["modelId"] as? String,
                   let provider = json["provider"] as? String {
                    model = RPCModel(
                        id: modelId,
                        name: nil,
                        api: nil,
                        provider: provider,
                        baseUrl: nil,
                        reasoning: nil,
                        contextWindow: nil,
                        maxTokens: nil
                    )
                }

            case "user":
                if let message = json["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    messages.append(RPCMessage(
                        id: json["id"] as? String ?? UUID().uuidString,
                        role: .user,
                        content: content,
                        timestamp: lastActivity
                    ))
                }

            case "assistant":
                if let message = json["message"] as? [String: Any],
                   let contentArray = message["content"] as? [[String: Any]] {
                    var text = ""
                    for block in contentArray {
                        if block["type"] as? String == "text",
                           let blockText = block["text"] as? String {
                            text += blockText
                        }
                    }
                    if !text.isEmpty {
                        messages.append(RPCMessage(
                            id: json["id"] as? String ?? UUID().uuidString,
                            role: .assistant,
                            content: text,
                            timestamp: lastActivity
                        ))
                    }
                }

            case "tool_use", "tool_result":
                // Could parse tool calls here
                break

            default:
                break
            }
        }

        // Skip sessions without a valid path
        guard !projectPath.isEmpty else { return nil }

        let session = ManagedSession(
            id: sessionId,
            workingDirectory: projectPath,
            isLive: false
        )
        session.messages = messages
        session.model = model
        session.lastActivity = lastActivity
        session.sessionFile = url.path

        // Capture file modification date to detect externally active sessions
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let modDate = attrs[.modificationDate] as? Date {
            session.fileModificationDate = modDate
        }

        return session
    }
}

// MARK: - ManagedSession

/// A session that can be either live (RPC) or historical (from JSONL)
@MainActor
@Observable
class ManagedSession: Identifiable, Equatable {
    let id: String

    nonisolated static func == (lhs: ManagedSession, rhs: ManagedSession) -> Bool {
        lhs.id == rhs.id
    }
    let workingDirectory: String
    var isLive: Bool

    // State
    var phase: RPCPhase = .disconnected
    var model: RPCModel?
    var availableModels: [RPCModel] = []
    var thinkingLevel: ThinkingLevel = .medium
    var isStreaming = false
    var streamingText = ""
    var streamingThinking = ""
    var messages: [RPCMessage] = []
    var currentTool: RPCToolExecution?
    var lastError: String?
    var lastActivity: Date = Date()
    var sessionFile: String?
    var fileModificationDate: Date?

    /// Whether this session appears to be active externally (file recently modified)
    var isLikelyExternallyActive: Bool {
        guard !isLive, let path = sessionFile else { return false }
        // Check current file modification time
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let modDate = attrs[.modificationDate] as? Date {
            // Consider active if modified within the last 30 seconds
            return Date().timeIntervalSince(modDate) < 30
        }
        return false
    }

    // RPC client (only for live sessions)
    private var rpcClient: PiRPCClient?

    var projectName: String {
        URL(fileURLWithPath: workingDirectory).lastPathComponent
    }

    init(id: String, workingDirectory: String, isLive: Bool) {
        self.id = id
        self.workingDirectory = workingDirectory
        self.isLive = isLive
        // Live sessions start in .starting phase since they'll connect immediately
        self.phase = isLive ? .starting : .disconnected
    }

    // MARK: - Lifecycle

    func start(provider: String? = nil, model: String? = nil, resumeSessionFile: String? = nil) async {
        guard isLive else { return }

        phase = .starting
        rpcClient = PiRPCClient()

        await setupCallbacks()

        do {
            logger.info("Starting RPC process for workDir: \(self.workingDirectory)")

            // Start without --session flag; use RPC commands instead
            try await rpcClient?.start(
                provider: provider,
                model: model,
                workingDirectory: workingDirectory,
                noSession: false,
                sessionFile: nil
            )

            logger.info("RPC process started, resumeSessionFile: \(resumeSessionFile ?? "nil")")

            // If resuming, switch to the session and load messages
            if let sessionPath = resumeSessionFile {
                try await rpcClient?.switchSession(sessionPath: sessionPath)

                if let messagesResponse = try await rpcClient?.getMessages() {
                    if let data = messagesResponse.data?.dictValue,
                       let messagesArray = data["messages"] as? [Any] {
                        let rawMessages = messagesArray.map { AnyCodable($0) }
                        handleMessagesLoaded(rawMessages)
                    }
                }
                self.sessionFile = sessionPath
            } else {
                // New session - create it and capture the session file
                logger.info("Creating new session...")
                try await rpcClient?.newSession()
            }

            // Get state to capture model, thinking level, etc.
            try await rpcClient?.getState()

            // Fetch available models
            await fetchAvailableModels()

            phase = .idle
            logger.info("Session started, phase=idle, messages count: \(self.messages.count)")
        } catch {
            logger.error("Session start failed: \(error.localizedDescription)")
            phase = .error(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func stop() async {
        await rpcClient?.stop()
        rpcClient = nil
        isLive = false
        phase = .disconnected
    }

    // MARK: - Commands

    func sendPrompt(_ text: String) async {
        guard isLive, let client = rpcClient else { return }

        let userMessage = RPCMessage(
            id: UUID().uuidString,
            role: .user,
            content: text,
            timestamp: Date()
        )
        messages.append(userMessage)
        lastActivity = Date()

        streamingText = ""
        isStreaming = true
        phase = .thinking

        do {
            try await client.prompt(text)
        } catch {
            lastError = error.localizedDescription
            isStreaming = false
            phase = .idle
        }
    }

    func abort() async {
        try? await rpcClient?.abort()
    }

    func cycleModel() async {
        try? await rpcClient?.cycleModel()
    }

    func cycleThinkingLevel() async {
        guard isLive, let client = rpcClient else { return }
        do {
            try await client.cycleThinkingLevel()
            // Small delay to let command process, then refresh state
            try await Task.sleep(for: .milliseconds(100))
            try await client.getState()
        } catch {
            logger.error("Failed to cycle thinking level: \(error.localizedDescription)")
        }
    }

    func fetchAvailableModels() async {
        guard isLive, let client = rpcClient else { return }
        do {
            availableModels = try await client.getAvailableModels()
            logger.info("Fetched \(self.availableModels.count) available models")
        } catch {
            logger.error("Failed to fetch models: \(error.localizedDescription)")
        }
    }

    func setModel(provider: String, modelId: String) async {
        guard isLive, let client = rpcClient else { return }
        do {
            try await client.setModel(provider: provider, modelId: modelId)
            // Refresh state to get updated model
            try await client.getState()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Models grouped by provider
    var modelsByProvider: [String: [RPCModel]] {
        Dictionary(grouping: availableModels, by: { $0.provider })
    }

    // MARK: - Callbacks

    private func setupCallbacks() async {
        guard let client = rpcClient else { return }

        await client.setCallbacks(
            onAgentStart: { [weak self] in
                self?.phase = .thinking
                self?.isStreaming = true
            },
            onAgentEnd: { [weak self] _ in
                self?.phase = .idle
                self?.isStreaming = false
                self?.finalizeStreamingMessage()
            },
            onMessageUpdate: { [weak self] message, delta in
                self?.handleMessageUpdate(delta)
            },
            onToolExecutionStart: { [weak self] toolCallId, toolName, args in
                self?.handleToolStart(toolCallId, toolName, args)
            },
            onToolExecutionUpdate: { [weak self] toolCallId, _, partialResult in
                self?.handleToolUpdate(toolCallId, partialResult)
            },
            onToolExecutionEnd: { [weak self] toolCallId, toolName, result, isError in
                self?.handleToolEnd(toolCallId, toolName, result, isError)
            },
            onStateChanged: { [weak self] state in
                self?.handleStateChanged(state)
            },
            onError: { [weak self] error in
                self?.lastError = error
            },
            onProcessTerminated: { [weak self] in
                self?.phase = .disconnected
                self?.isLive = false
            },
            onMessagesLoaded: { [weak self] messages in
                self?.handleMessagesLoaded(messages)
            },
            onSessionSwitched: { [weak self] sessionFile in
                if let sessionFile {
                    self?.sessionFile = sessionFile
                }
            }
        )
    }

    private func handleMessageUpdate(_ delta: AssistantMessageEvent) {
        lastActivity = Date()

        switch delta.type {
        case "text_delta":
            if let text = delta.delta {
                streamingText += text
            }
        case "thinking_delta", "thinking_start":
            if let text = delta.delta ?? delta.thinking {
                streamingThinking += text
            }
        case "thinking_end":
            break
        case "toolcall_start":
            phase = .executing
        case "done":
            finalizeStreamingMessage()
        case "error":
            if let reason = delta.reason {
                lastError = reason
            }
            isStreaming = false
            phase = .idle
        default:
            break
        }
    }

    private func finalizeStreamingMessage() {
        guard !streamingText.isEmpty else { return }

        let message = RPCMessage(
            id: UUID().uuidString,
            role: .assistant,
            content: streamingText,
            timestamp: Date()
        )
        messages.append(message)
        streamingText = ""
        streamingThinking = ""
        lastActivity = Date()
    }

    private func handleToolStart(_ toolCallId: String, _ toolName: String, _ args: [String: Any]) {
        phase = .executing
        currentTool = RPCToolExecution(
            id: toolCallId,
            name: toolName,
            args: args,
            status: .running,
            partialOutput: nil,
            result: nil
        )

        messages.append(RPCMessage(
            id: toolCallId,
            role: .tool,
            toolName: toolName,
            toolArgs: args,
            timestamp: Date()
        ))
        lastActivity = Date()
    }

    private func handleToolUpdate(_ toolCallId: String, _ partialResult: AnyCodable?) {
        if var tool = currentTool, tool.id == toolCallId {
            tool.partialOutput = partialResult?.stringValue
            currentTool = tool
        }
    }

    private func handleToolEnd(_ toolCallId: String, _ toolName: String, _ result: AnyCodable?, _ isError: Bool) {
        if var tool = currentTool, tool.id == toolCallId {
            tool.status = isError ? .error : .success
            tool.result = extractResultText(from: result)
            currentTool = tool

            if let index = messages.lastIndex(where: { $0.id == toolCallId }) {
                var message = messages[index]
                message.toolResult = tool.result
                message.toolStatus = tool.status
                messages[index] = message
            }
        }
        currentTool = nil
        lastActivity = Date()
    }

    private func handleStateChanged(_ state: RPCSessionState) {
        model = state.model
        if let level = state.thinkingLevel, let parsed = ThinkingLevel(rawValue: level) {
            thinkingLevel = parsed
        }
        // Capture session file if available
        if let file = state.sessionFile {
            sessionFile = file
        }
    }

    private func handleMessagesLoaded(_ rawMessages: [AnyCodable]) {
        logger.info("handleMessagesLoaded called with \(rawMessages.count) raw messages")
        var loadedMessages: [RPCMessage] = []
        var toolCallIndex: [String: Int] = [:]

        for rawMessage in rawMessages {
            guard let dict = rawMessage.dictValue,
                  let role = dict["role"] as? String else {
                continue
            }

            let id = dict["id"] as? String ?? UUID().uuidString
            let timestamp = Date()

            switch role {
            case "user":
                if let text = extractTextContent(from: dict["content"]) {
                    loadedMessages.append(RPCMessage(
                        id: id,
                        role: .user,
                        content: text,
                        timestamp: timestamp
                    ))
                }

            case "assistant":
                if let contentArray = dict["content"] as? [[String: Any]] {
                    for block in contentArray {
                        guard let blockType = block["type"] as? String else { continue }

                        switch blockType {
                        case "text":
                            if let text = block["text"] as? String, !text.isEmpty {
                                loadedMessages.append(RPCMessage(
                                    id: UUID().uuidString,
                                    role: .assistant,
                                    content: text,
                                    timestamp: timestamp
                                ))
                            }
                        case "toolCall", "tool_use":
                            if let toolId = block["id"] as? String,
                               let toolName = (block["name"] ?? block["toolName"]) as? String {
                                let args = block["arguments"] as? [String: Any] ?? block["input"] as? [String: Any]
                                loadedMessages.append(RPCMessage(
                                    id: toolId,
                                    role: .tool,
                                    toolName: toolName,
                                    toolArgs: args,
                                    toolStatus: .running,
                                    timestamp: timestamp
                                ))
                                toolCallIndex[toolId] = loadedMessages.count - 1
                            }
                        default:
                            break
                        }
                    }
                }

            case "toolResult", "tool":
                if let toolCallId = dict["toolCallId"] as? String,
                   let index = toolCallIndex[toolCallId] {
                    let output = extractTextContent(from: dict["content"])
                    let isError = dict["isError"] as? Bool ?? false
                    var msg = loadedMessages[index]
                    msg.toolResult = output
                    msg.toolStatus = isError ? .error : .success
                    loadedMessages[index] = msg
                }

            default:
                break
            }
        }

        messages = loadedMessages
        logger.info("Loaded \(loadedMessages.count) messages from session")
    }

    private func extractTextContent(from content: Any?) -> String? {
        guard let content else { return nil }

        if let text = content as? String {
            return text
        }

        if let contentArray = content as? [[String: Any]] {
            return contentArray.compactMap { block -> String? in
                if block["type"] as? String == "text" {
                    return block["text"] as? String
                }
                return nil
            }.joined(separator: "\n")
        }

        return nil
    }

    private func extractResultText(from result: AnyCodable?) -> String? {
        guard let result = result else { return nil }

        if let dict = result.dictValue,
           let content = dict["content"] as? [[String: Any]],
           let first = content.first,
           let text = first["text"] as? String {
            return text
        }

        return result.stringValue
    }
}
