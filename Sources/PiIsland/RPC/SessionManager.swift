import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pi-island", category: "SessionManager")

// Debug file logging
private func debugLog(_ message: String) {
    let logFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pi-island-debug.log")
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFile.path) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: logFile)
        }
    }
}

/// Manages multiple Pi RPC sessions
@MainActor
@Observable
class SessionManager {
    /// All sessions (live RPC + historical)
    private(set) var sessions: [String: ManagedSession] = [:]

    /// Currently selected session ID
    var selectedSessionId: String?

    /// Callback when an agent completes a response (for hint animations)
    var onAgentCompleted: ((ManagedSession) -> Void)?

    /// Callback when an external session is updated (for hint animations)
    var onExternalSessionUpdated: ((ManagedSession) -> Void)?

    /// Callback when a session is resumed (old session replaced with new live one)
    var onSessionResumed: ((_ oldSession: ManagedSession, _ newSession: ManagedSession) -> Void)?

    /// File watcher for real-time session updates
    private let fileWatcher = SessionFileWatcher()

    /// Maps session file paths to session IDs for quick lookup
    private var sessionFileIndex: [String: String] = [:]

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

        // Set up callback for visual hints
        session.onAgentCompleted = { [weak self, weak session] in
            guard let self = self, let session = session else { return }
            self.onAgentCompleted?(session)
        }

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
    /// This method returns quickly with a session that has messages loaded.
    /// The RPC connection happens in the background.
    func resumeSession(_ session: ManagedSession) async -> ManagedSession? {
        logger.info("resumeSession called for session \(session.id), isLive=\(session.isLive), sessionFile=\(session.sessionFile ?? "nil")")

        guard !session.isLive, let sessionFile = session.sessionFile else {
            logger.warning("Cannot resume: session is already live or has no session file")
            return nil
        }

        // Check if there's already a live session for this working directory
        if let existingLive = liveSessions.first(where: { $0.workingDirectory == session.workingDirectory }) {
            logger.info("Found existing live session for \(session.workingDirectory), reusing it")
            selectedSessionId = existingLive.id
            return existingLive
        }

        // Remove the historical session since we're resuming it
        sessions.removeValue(forKey: session.id)

        // Create a new live session - starts in .starting phase
        let newSession = ManagedSession(
            id: UUID().uuidString,
            workingDirectory: session.workingDirectory,
            isLive: true
        )

        // Set up callback for visual hints
        newSession.onAgentCompleted = { [weak self, weak newSession] in
            guard let self = self, let session = newSession else { return }
            self.onAgentCompleted?(session)
        }

        // Copy messages from historical session (instant - user sees content immediately)
        newSession.messages = session.messages
        newSession.model = session.model
        newSession.lastActivity = Date()
        newSession.sessionFile = sessionFile

        sessions[newSession.id] = newSession

        // Update the file index to point to the new session
        sessionFileIndex[sessionFile] = newSession.id

        // Clean up any remaining duplicates
        cleanupDuplicateSessions()

        selectedSessionId = newSession.id

        // Notify that session was resumed (so views can update)
        onSessionResumed?(session, newSession)

        // Start RPC process in background - don't await here!
        // The session is already visible with messages, RPC connects async
        Task {
            logger.info("Starting RPC connection in background for: \(sessionFile)")
            await newSession.start(resumeSessionFile: sessionFile)
            logger.info("RPC connection established for: \(sessionFile)")
        }

        logger.info("Resumed session instantly, messages count: \(newSession.messages.count)")
        return newSession
    }

    /// Refresh sessions by cleaning up duplicates and stale data
    func refreshSessions() {
        cleanupDuplicateSessions()
        cleanupErroredSessions()
    }

    /// Remove errored live sessions that are no longer useful
    private func cleanupErroredSessions() {
        var toRemove: [String] = []
        for (id, session) in sessions where session.isLive {
            if case .error = session.phase {
                // Check if there's another healthy live session for the same project
                let hasHealthySession = liveSessions.contains { other in
                    guard other.id != id else { return false }
                    guard other.workingDirectory == session.workingDirectory else { return false }
                    if case .error = other.phase { return false }
                    return true
                }
                if hasHealthySession {
                    toRemove.append(id)
                }
            }
        }

        for id in toRemove {
            if let session = sessions[id] {
                Task {
                    await session.stop()
                }
            }
            sessions.removeValue(forKey: id)
            logger.info("Removed errored duplicate session: \(id)")
        }
    }

    /// Start watching for file system changes
    func startWatching() {
        setupFileWatcherCallbacks()
        fileWatcher.startWatching()
    }

    /// Stop watching for file system changes
    func stopWatching() {
        fileWatcher.stopWatching()
    }

    private func setupFileWatcherCallbacks() {
        fileWatcher.onSessionCreated = { [weak self] (url: URL) in
            Task { @MainActor in
                self?.cleanupDuplicateSessions()
                await self?.handleSessionFileCreated(url)
            }
        }

        fileWatcher.onSessionModified = { [weak self] (url: URL) in
            Task { @MainActor in
                self?.cleanupDuplicateSessions()
                await self?.handleSessionFileModified(url)
            }
        }

        fileWatcher.onSessionDeleted = { [weak self] (url: URL) in
            Task { @MainActor in
                self?.handleSessionFileDeleted(url)
            }
        }
    }

    /// Remove historical sessions that have the same file path as a live session
    private func cleanupDuplicateSessions() {
        let liveFilePaths = Set(liveSessions.compactMap { $0.sessionFile })

        // Find historical sessions with the same file paths
        var toRemove: [String] = []
        for (id, session) in sessions where !session.isLive {
            if let path = session.sessionFile, liveFilePaths.contains(path) {
                toRemove.append(id)
            }
        }

        // Remove duplicates
        for id in toRemove {
            sessions.removeValue(forKey: id)
            logger.info("Removed duplicate historical session: \(id)")
        }

        // Also clean up the file index
        for (path, id) in sessionFileIndex {
            if toRemove.contains(id) {
                sessionFileIndex.removeValue(forKey: path)
            }
        }
    }

    private func handleSessionFileCreated(_ url: URL) async {
        let filePath = url.path

        // Skip if this file is already used by a live session
        let usedByLive = liveSessions.contains { $0.sessionFile == filePath }
        if usedByLive {
            logger.debug("Skipping new file that belongs to live session: \(filePath)")
            return
        }

        // Skip if already indexed
        if sessionFileIndex[filePath] != nil {
            return
        }

        // Parse in background
        let sessionData = await Task.detached {
            parseSessionFileBackground(url)
        }.value

        guard let data = sessionData else { return }

        // Don't overwrite existing sessions
        if sessions[data.id] == nil {
            let session = ManagedSession(id: data.id, workingDirectory: data.workingDirectory, isLive: false)
            session.messages = data.messages
            session.model = data.model
            session.lastActivity = data.lastActivity
            session.sessionFile = filePath
            session.fileModificationDate = data.fileModificationDate
            
            sessions[session.id] = session
            sessionFileIndex[filePath] = session.id
            logger.info("Added new session from file: \(session.projectName)")
        }
    }

    private func handleSessionFileModified(_ url: URL) async {
        let filePath = url.path
        logger.debug("[DEBUG] handleSessionFileModified: \(filePath)")

        // Check if ACTIVE live session is using this file (skip if so)
        for session in liveSessions {
            if session.sessionFile == filePath {
                if session.isStreaming || session.phase == .thinking || session.phase == .executing {
                     // Update mod date but don't re-parse while active
                    session.fileModificationDate = Date()
                    logger.debug("[DEBUG] Skipping update for live session (active): \(filePath)")
                    return
                }
                logger.debug("[DEBUG] Live session found but idle, processing external update: \(filePath)")
            }
        }

        // Parse in background
        logger.debug("[DEBUG] Starting background parse for: \(filePath)")
        let sessionData = await Task.detached {
            parseSessionFileBackground(url)
        }.value

        guard let data = sessionData else {
            logger.error("[DEBUG] Failed to parse session data for: \(filePath)")
            return
        }
        logger.debug("[DEBUG] Serialized data ready for: \(data.id), messages: \(data.messages.count)")

        // Find the session for this file by path
        if let sessionId = sessionFileIndex[filePath],
           let existingSession = sessions[sessionId] {

            logger.debug("[DEBUG] Updating existing session: \(existingSession.projectName)")

            // Check if data actually changed before updating
            let previousMessageCount = existingSession.messages.count
            let hasChanges = previousMessageCount != data.messages.count ||
                           existingSession.lastActivity != data.lastActivity

            guard hasChanges else {
                logger.debug("[DEBUG] No changes detected for \(existingSession.projectName), skipping update")
                // Still update mod date
                existingSession.fileModificationDate = data.fileModificationDate
                return
            }

            // Update modification date first
            existingSession.fileModificationDate = data.fileModificationDate

            // Apply updates - @Observable should trigger automatically
            existingSession.messages = data.messages
            existingSession.lastActivity = data.lastActivity
            if data.model != nil {
                existingSession.model = data.model
            }

            // For dictionary observation, we need to trigger a change
            // by re-assigning the session to the dictionary
            sessions[sessionId] = existingSession

            // Notify about external update for visual hints
            logger.info("[DEBUG] Session \(existingSession.projectName) updated (\(previousMessageCount) -> \(existingSession.messages.count) messages)")
            onExternalSessionUpdated?(existingSession)

        } else {
            logger.debug("[DEBUG] New session file detected: \(filePath)")

            // Unknown file - add it
            // Verify no other session
            let existingByPath = sessions.values.first { $0.sessionFile == filePath }
            if let existing = existingByPath {
                sessionFileIndex[filePath] = existing.id
                existing.fileModificationDate = data.fileModificationDate
                return
            }

            // Create new
            let session = ManagedSession(id: data.id, workingDirectory: data.workingDirectory, isLive: false)
            session.messages = data.messages
            session.model = data.model
            session.lastActivity = data.lastActivity
            session.sessionFile = filePath
            session.fileModificationDate = data.fileModificationDate

            sessions[session.id] = session
            sessionFileIndex[filePath] = session.id
            logger.info("[DEBUG] Added session from modified file: \(session.projectName)")
        }
    }

    private func handleSessionFileDeleted(_ url: URL) {
        let filePath = url.path

        // Find and remove the session
        if let sessionId = sessionFileIndex[filePath] {
            // Don't remove live sessions
            if let session = sessions[sessionId], !session.isLive {
                sessions.removeValue(forKey: sessionId)
                sessionFileIndex.removeValue(forKey: filePath)
                logger.info("Removed session for deleted file: \(filePath)")

                // Clear selection if needed
                if selectedSessionId == sessionId {
                    selectedSessionId = liveSessions.first?.id
                }
            }
        }
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
            
            // Gather all candidate files first
            var candidateFiles: [URL] = []

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
                
                // Keep top 3 per project
                candidateFiles.append(contentsOf: sortedFiles.prefix(3))
            }
            
            // Parse in parallel
            var loadedCount = 0
            
            await withTaskGroup(of: SerializedSessionData?.self) { group in
                for file in candidateFiles {
                    let filePath = file.path
                    
                    // Skip if used by live session
                    if liveSessions.contains(where: { $0.sessionFile == filePath }) { continue }
                    
                    // Skip if already indexed
                    if sessionFileIndex[filePath] != nil { continue }
                    
                    group.addTask {
                        parseSessionFileBackground(file)
                    }
                }
                
                for await sessionData in group {
                    guard let data = sessionData else { continue }
                    
                    // Update on main actor
                    if sessions[data.id] == nil {
                        let session = ManagedSession(id: data.id, workingDirectory: data.workingDirectory, isLive: false)
                        session.messages = data.messages
                        session.model = data.model
                        session.lastActivity = data.lastActivity
                        session.sessionFile = candidateFiles.first(where: { $0.path.contains(data.id) })?.path // Best effort match or we store path in data
                        
                        // We need the file path. Let's update SerializedSessionData to arguably include it or just rely on the fact we had it.
                        // Actually, parseSessionFileBackground doesn't return the full path in struct, but we need it.
                        // Let's rely on re-constructing it or better, updating the struct to include 'filePath'.
                        // Wait, I can't easily change the struct in this replace call without breaking the previous one.
                        // Actually, I can just not use the filePath from the struct but use a tuple in group.
                    }
                }
            }
            
            // Re-implementation with tuple to keep track of file path
            await withTaskGroup(of: (URL, SerializedSessionData?).self) { group in
                for file in candidateFiles {
                    let filePath = file.path
                    if liveSessions.contains(where: { $0.sessionFile == filePath }) { continue }
                    if sessionFileIndex[filePath] != nil { continue }
                    
                    group.addTask {
                        return (file, parseSessionFileBackground(file))
                    }
                }
                
                for await (url, sessionData) in group {
                    guard let data = sessionData else { continue }
                    let filePath = url.path
                    
                    if sessions[data.id] == nil {
                        let session = ManagedSession(id: data.id, workingDirectory: data.workingDirectory, isLive: false)
                        session.messages = data.messages
                        session.model = data.model
                        session.lastActivity = data.lastActivity
                        session.sessionFile = filePath
                        session.fileModificationDate = data.fileModificationDate
                        
                        sessions[session.id] = session
                        sessionFileIndex[filePath] = session.id
                        loadedCount += 1
                    }
                }
            }

            logger.info("Loaded \(loadedCount) historical sessions")
        } catch {
            logger.error("Error loading sessions: \(error.localizedDescription)")
        }
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
    /// This is a cached value updated by the file watcher - no disk I/O in getter
    var isLikelyExternallyActive: Bool {
        guard !isLive else { return false }
        guard let modDate = fileModificationDate else { return false }
        return Date().timeIntervalSince(modDate) < 30
    }

    /// Whether this session appears to be waiting for a response (user message without reply)
    /// This is a cached value - no disk I/O in getter
    var isLikelyThinking: Bool {
        guard !isLive else { return false }
        // Check if the last message is from user (waiting for assistant)
        guard let lastMessage = messages.last, lastMessage.role == .user else { return false }
        // And the file was recently modified (within 60 seconds)
        guard let modDate = fileModificationDate else { return false }
        return Date().timeIntervalSince(modDate) < 60
    }

    // RPC client (only for live sessions)
    private var rpcClient: PiRPCClient?

    /// Callback when agent completes a response (for visual hints)
    var onAgentCompleted: (() -> Void)?

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
        // Explicit array reassignment to ensure @Observable triggers
        var updatedMessages = messages
        updatedMessages.append(userMessage)
        messages = updatedMessages
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
                // Notify for visual hint
                self?.onAgentCompleted?()
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
                logger.debug("[THINKING] Updated, length: \(self.streamingThinking.count)")
            }
        case "thinking_end":
            logger.debug("[THINKING] Ended, final length: \(self.streamingThinking.count)")
            break
        case "toolcall_start":
            logger.debug("[TOOL] toolcall_start event")
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
        // Explicit array reassignment to ensure @Observable triggers
        var updatedMessages = messages
        updatedMessages.append(message)
        messages = updatedMessages
        streamingText = ""
        streamingThinking = ""
        lastActivity = Date()
    }

    private func handleToolStart(_ toolCallId: String, _ toolName: String, _ args: [String: Any]) {
        logger.debug("[TOOL] handleToolStart: \(toolName) (\(toolCallId))")
        phase = .executing
        let codableArgs = args.mapValues { AnyCodable($0) }

        currentTool = RPCToolExecution(
            id: toolCallId,
            name: toolName,
            args: codableArgs,
            status: .running,
            partialOutput: nil,
            result: nil
        )
        logger.debug("[TOOL] currentTool set: \(toolName)")

        // Explicit array reassignment to ensure @Observable triggers
        var updatedMessages = messages
        updatedMessages.append(RPCMessage(
            id: toolCallId,
            role: .tool,
            toolName: toolName,
            toolArgs: codableArgs,
            timestamp: Date()
        ))
        messages = updatedMessages
        logger.debug("[TOOL] Tool message appended, total messages: \(self.messages.count)")
        lastActivity = Date()
    }

    private func handleToolUpdate(_ toolCallId: String, _ partialResult: AnyCodable?) {
        guard let tool = currentTool, tool.id == toolCallId else { return }
        // Create new tool instance to ensure observation triggers
        currentTool = RPCToolExecution(
            id: tool.id,
            name: tool.name,
            args: tool.args,
            status: tool.status,
            partialOutput: partialResult?.stringValue,
            result: tool.result
        )
    }

    private func handleToolEnd(_ toolCallId: String, _ toolName: String, _ result: AnyCodable?, _ isError: Bool) {
        if var tool = currentTool, tool.id == toolCallId {
            tool.status = isError ? .error : .success
            tool.result = extractResultText(from: result)
            currentTool = tool

            if let index = messages.lastIndex(where: { $0.id == toolCallId }) {
                // Explicit array reassignment to ensure @Observable triggers
                var updatedMessages = messages
                var message = updatedMessages[index]
                message.toolResult = tool.result
                message.toolStatus = tool.status
                updatedMessages[index] = message
                messages = updatedMessages
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
                                let codableArgs = args?.mapValues { AnyCodable($0) }
                                
                                loadedMessages.append(RPCMessage(
                                    id: toolId,
                                    role: .tool,
                                    toolName: toolName,
                                    toolArgs: codableArgs,
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
// MARK: - Background Parsing

private struct SerializedSessionData: Sendable {
    let id: String
    let workingDirectory: String
    let messages: [RPCMessage]
    let model: RPCModel?
    let lastActivity: Date
    let fileModificationDate: Date
    
    var projectName: String {
        URL(fileURLWithPath: workingDirectory).lastPathComponent
    }
}

/// Helper to parse session files off the main actor
private nonisolated func parseSessionFileBackground(_ url: URL) -> SerializedSessionData? {
    // 1. Read file data (Synchronous I/O, but running on background thread)
    guard let data = try? Data(contentsOf: url),
          let content = String(data: data, encoding: .utf8) else {
        return nil
    }

    let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
    guard !lines.isEmpty else { return nil }

    // 2. Parse Filename for ID
    let filename = url.deletingPathExtension().lastPathComponent
    let sessionId = filename.components(separatedBy: "_").last ?? filename

    var projectPath = ""
    var messages: [RPCMessage] = []
    var model: RPCModel?
    var lastActivity = Date.distantPast

    // 3. Iterate lines
    for line in lines {
        guard let lineData = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
            continue
        }

        // Parse timestamp
        if let tsString = json["timestamp"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: tsString), date > lastActivity {
                lastActivity = date
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

        case "message":
            guard let messageObj = json["message"] as? [String: Any],
                  let role = messageObj["role"] as? String else { continue }
            
            let messageId = json["id"] as? String ?? UUID().uuidString

            switch role {
            case "user":
                if let contentArray = messageObj["content"] as? [[String: Any]] {
                    var text = ""
                    for block in contentArray {
                        if block["type"] as? String == "text",
                           let blockText = block["text"] as? String {
                            text += blockText
                        }
                    }
                    if !text.isEmpty {
                        messages.append(RPCMessage(id: messageId, role: .user, content: text, timestamp: lastActivity))
                    }
                } else if let content = messageObj["content"] as? String {
                    messages.append(RPCMessage(id: messageId, role: .user, content: content, timestamp: lastActivity))
                }

            case "assistant":
                if let contentArray = messageObj["content"] as? [[String: Any]] {
                    var text = ""
                    for block in contentArray {
                        if block["type"] as? String == "text",
                           let blockText = block["text"] as? String {
                            text += blockText
                        } else if block["type"] as? String == "toolCall" || block["type"] as? String == "tool_use",
                                  let toolId = block["id"] as? String,
                                  let toolName = (block["name"] ?? block["toolName"]) as? String {
                            // Extract tool call
                            let args = block["arguments"] as? [String: Any] ?? block["input"] as? [String: Any]
                            let codableArgs = args?.mapValues { AnyCodable($0) }
                            messages.append(RPCMessage(
                                id: toolId,
                                role: .tool,
                                toolName: toolName,
                                toolArgs: codableArgs,
                                toolStatus: .running,
                                timestamp: lastActivity
                            ))
                        }
                    }
                    if !text.isEmpty {
                        messages.append(RPCMessage(id: messageId, role: .assistant, content: text, timestamp: lastActivity))
                    }
                }

            case "toolResult", "tool":
                // Find the matching tool call and update it
                if let toolCallId = messageObj["toolCallId"] as? String ?? messageObj["toolCallId"] as? String,
                   let content = messageObj["content"],
                   let index = messages.lastIndex(where: { $0.id == toolCallId && $0.role == .tool }) {
                    // Extract text from content (inline version for background parser)
                    let output: String? = {
                        if let text = content as? String { return text }
                        if let arr = content as? [[String: Any]] {
                            return arr.compactMap { $0["text"] as? String }.joined(separator: "\n")
                        }
                        return nil
                    }()
                    let isError = messageObj["isError"] as? Bool ?? false
                    var msg = messages[index]
                    msg.toolResult = output
                    msg.toolStatus = isError ? .error : .success
                    messages[index] = msg
                }

            default: break
            }

        default: break
        }
    }

    guard !projectPath.isEmpty else { return nil }

    // Capture modification date
    var modDate = Date()
    if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
       let date = attrs[.modificationDate] as? Date {
        modDate = date
    }

    return SerializedSessionData(
        id: sessionId,
        workingDirectory: projectPath,
        messages: messages,
        model: model,
        lastActivity: lastActivity,
        fileModificationDate: modDate
    )
}
