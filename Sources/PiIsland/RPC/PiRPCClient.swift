import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pi-island", category: "PiRPCClient")

/// Manages a Pi agent process in RPC mode
actor PiRPCClient {
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var readBuffer = Data()

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    // Event callbacks (called on MainActor)
    var onEvent: (@MainActor (RPCEvent) -> Void)?

    // Convenience callbacks
    var onAgentStart: (@MainActor () -> Void)?
    var onAgentEnd: (@MainActor ([AnyCodable]) -> Void)?
    var onMessageStart: (@MainActor (AnyCodable) -> Void)?
    var onMessageUpdate: (@MainActor (AnyCodable, AssistantMessageEvent) -> Void)?
    var onMessageEnd: (@MainActor (AnyCodable) -> Void)?
    var onToolExecutionStart: (@MainActor (String, String, [String: Any]) -> Void)?
    var onToolExecutionUpdate: (@MainActor (String, String, AnyCodable?) -> Void)?
    var onToolExecutionEnd: (@MainActor (String, String, AnyCodable?, Bool) -> Void)?
    var onStateChanged: (@MainActor (RPCSessionState) -> Void)?
    var onError: (@MainActor (String) -> Void)?
    var onProcessTerminated: (@MainActor () -> Void)?
    var onMessagesLoaded: (@MainActor ([AnyCodable]) -> Void)?
    var onSessionSwitched: (@MainActor (String?) -> Void)?

    // State
    private(set) var isRunning = false
    private(set) var currentState: RPCSessionState?

    // Pending requests tracking (for request/response pattern)
    private var pendingRequests: [String: Bool] = [:]
    private var pendingResponses: [String: RPCEvent] = [:]

    // MARK: - Lifecycle

    /// Start the Pi agent process
    func start(
        provider: String? = nil,
        model: String? = nil,
        workingDirectory: String? = nil,
        noSession: Bool = false,
        sessionFile: String? = nil
    ) async throws {
        guard !isRunning else {
            logger.warning("Already running")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")

        var args = ["pi", "--mode", "rpc"]
        if let provider = provider {
            args.append(contentsOf: ["--provider", provider])
        }
        if let model = model {
            args.append(contentsOf: ["--model", model])
        }
        if noSession {
            args.append("--no-session")
        }
        if let sessionFile = sessionFile {
            args.append(contentsOf: ["--session", sessionFile])
        }
        process.arguments = args

        if let workingDirectory = workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        // Set up pipes
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Handle stdout
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.handleStdout(data) }
        }

        // Handle stderr (log only)
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                logger.warning("stderr: \(text)")
            }
        }

        // Handle termination
        process.terminationHandler = { [weak self] proc in
            logger.info("Process terminated with code \(proc.terminationStatus)")
            Task { await self?.handleTermination() }
        }

        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe

        do {
            try process.run()
            isRunning = true
            logger.info("Started Pi RPC process (PID: \(process.processIdentifier))")
        } catch {
            logger.error("Failed to start process: \(error.localizedDescription)")
            throw error
        }
    }

    /// Stop the Pi agent process
    func stop() {
        guard isRunning, let process = process else { return }

        logger.info("Stopping Pi RPC process")

        // Clean up handlers first
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        // Terminate
        if process.isRunning {
            process.terminate()
        }

        self.process = nil
        self.stdinPipe = nil
        self.stdoutPipe = nil
        self.stderrPipe = nil
        self.readBuffer = Data()
        self.isRunning = false
    }

    // MARK: - Commands

    /// Send a prompt to the agent
    func prompt(_ message: String, images: [ImageData]? = nil) async throws {
        try await send(.prompt(message: message, images: images))
    }

    /// Send a steering message (interrupts mid-run)
    func steer(_ message: String) async throws {
        try await send(.steer(message: message))
    }

    /// Send a follow-up message (queued for after completion)
    func followUp(_ message: String) async throws {
        try await send(.followUp(message: message))
    }

    /// Abort current operation
    func abort() async throws {
        try await send(.abort)
    }

    /// Get current state
    func getState() async throws {
        try await send(.getState)
    }

    /// Get available models
    func getAvailableModels() async throws -> [RPCModel] {
        let response = try await sendAndWait(.getAvailableModels, commandName: "get_available_models")
        if let data = response.data?.dictValue,
           let modelsArray = data["models"] as? [[String: Any]] {
            let jsonData = try JSONSerialization.data(withJSONObject: modelsArray)
            let decoder = JSONDecoder()
            return (try? decoder.decode([RPCModel].self, from: jsonData)) ?? []
        }
        return []
    }

    /// Set the model
    func setModel(provider: String, modelId: String) async throws {
        _ = try await sendAndWait(.setModel(provider: provider, modelId: modelId), commandName: "set_model")
    }

    /// Cycle to next model
    func cycleModel() async throws {
        try await send(.cycleModel)
    }

    /// Cycle thinking level
    func cycleThinkingLevel() async throws {
        try await send(.cycleThinkingLevel)
    }

    /// Set thinking level
    func setThinkingLevel(_ level: ThinkingLevel) async throws {
        try await send(.setThinkingLevel(level: level))
    }

    /// Compact context
    func compact(instructions: String? = nil) async throws {
        try await send(.compact(customInstructions: instructions))
    }

    /// Start new session
    func newSession() async throws {
        _ = try await sendAndWait(.newSession(), commandName: "new_session")
    }

    /// Switch to an existing session
    func switchSession(sessionPath: String) async throws {
        _ = try await sendAndWait(.switchSession(sessionPath: sessionPath), commandName: "switch_session")
    }

    /// Get messages from current session
    func getMessages() async throws -> RPCEvent {
        try await sendAndWait(.getMessages, commandName: "get_messages")
    }

    /// Get session stats
    func getSessionStats() async throws {
        try await send(.getSessionStats)
    }

    // MARK: - Private

    private func send(_ command: RPCCommand) async throws {
        guard isRunning, let stdinPipe = stdinPipe else {
            throw RPCError.notRunning
        }

        let data = try encoder.encode(command)
        guard var jsonString = String(data: data, encoding: .utf8) else {
            throw RPCError.encodingFailed
        }
        jsonString += "\n"

        guard let lineData = jsonString.data(using: .utf8) else {
            throw RPCError.encodingFailed
        }

        try stdinPipe.fileHandleForWriting.write(contentsOf: lineData)
        logger.debug("Sent: \(jsonString.trimmingCharacters(in: .newlines))")
    }

    /// Send a command and wait for the response
    private func sendAndWait(_ command: RPCCommand, commandName: String, timeout: Duration = .seconds(10)) async throws -> RPCEvent {
        guard isRunning, let stdinPipe = stdinPipe else {
            throw RPCError.notRunning
        }

        let data = try encoder.encode(command)
        guard var jsonString = String(data: data, encoding: .utf8) else {
            throw RPCError.encodingFailed
        }
        jsonString += "\n"

        guard let lineData = jsonString.data(using: .utf8) else {
            throw RPCError.encodingFailed
        }

        pendingRequests[commandName] = true

        do {
            try stdinPipe.fileHandleForWriting.write(contentsOf: lineData)
        } catch {
            throw error
        }

        // Wait for response with timeout
        let startTime = ContinuousClock.now
        while ContinuousClock.now - startTime < timeout {
            try await Task.sleep(for: .milliseconds(50))
            if let response = pendingResponses.removeValue(forKey: commandName) {
                return response
            }
        }
        throw RPCError.commandFailed("Timeout waiting for \(commandName)")
    }

    private func handleStdout(_ data: Data) async {
        readBuffer.append(data)

        // Process complete lines
        while let newlineIndex = readBuffer.firstIndex(of: 0x0A) { // \n
            let lineData = readBuffer[..<newlineIndex]
            readBuffer = Data(readBuffer[(newlineIndex + 1)...])

            guard !lineData.isEmpty else { continue }

            do {
                let event = try decoder.decode(RPCEvent.self, from: lineData)
                await processEvent(event)
            } catch {
                if let text = String(data: lineData, encoding: .utf8) {
                    logger.warning("Failed to parse: \(text)")
                }
            }
        }
    }

    private func processEvent(_ event: RPCEvent) async {
        logger.info("Event received: type=\(event.type), command=\(event.command ?? "nil")")

        // Forward raw event
        if let callback = onEvent {
            await MainActor.run { callback(event) }
        }

        // Handle specific events
        switch event.type {
        case "response":
            await handleResponse(event)

        case "agent_start":
            if let callback = onAgentStart {
                await MainActor.run { callback() }
            }

        case "agent_end":
            if let callback = onAgentEnd, let messages = event.messages {
                await MainActor.run { callback(messages) }
            }

        case "message_start":
            if let callback = onMessageStart, let message = event.message {
                await MainActor.run { callback(message) }
            }

        case "message_update":
            logger.info("message_update: hasMessage=\(event.message != nil), hasDelta=\(event.assistantMessageEvent != nil)")
            if let callback = onMessageUpdate,
               let message = event.message,
               let delta = event.assistantMessageEvent {
                await MainActor.run { callback(message, delta) }
            } else if let callback = onMessageUpdate,
                      let delta = event.assistantMessageEvent {
                // Some events don't have message, just delta
                await MainActor.run { callback(AnyCodable([:]), delta) }
            }

        case "message_end":
            if let callback = onMessageEnd, let message = event.message {
                await MainActor.run { callback(message) }
            }

        case "tool_execution_start":
            if let callback = onToolExecutionStart,
               let toolCallId = event.toolCallId,
               let toolName = event.toolName {
                let args = event.args?.mapValues { $0.value } ?? [:]
                await MainActor.run { callback(toolCallId, toolName, args) }
            }

        case "tool_execution_update":
            if let callback = onToolExecutionUpdate,
               let toolCallId = event.toolCallId,
               let toolName = event.toolName {
                let partialResult = event.partialResult
                await MainActor.run { callback(toolCallId, toolName, partialResult) }
            }

        case "tool_execution_end":
            if let callback = onToolExecutionEnd,
               let toolCallId = event.toolCallId,
               let toolName = event.toolName {
                let result = event.result
                let isError = event.isError ?? false
                await MainActor.run { callback(toolCallId, toolName, result, isError) }
            }

        case "extension_error":
            if let callback = onError, let error = event.error ?? event.errorMessage {
                await MainActor.run { callback(error) }
            }

        default:
            break
        }
    }

    private func handleResponse(_ event: RPCEvent) async {
        guard let command = event.command else { return }
        print("[handleResponse] command=\(command)")

        // Store response for polling-based waiting
        if pendingRequests.keys.contains(command) {
            print("[handleResponse] Storing response for \(command)")
            pendingResponses[command] = event
            pendingRequests.removeValue(forKey: command)
        }

        if event.success == false, let error = event.error {
            logger.error("Command \(command) failed: \(error)")
            if let callback = onError {
                await MainActor.run { callback(error) }
            }
            return
        }

        switch command {
        case "get_state":
            if let data = event.data?.dictValue {
                if let stateData = try? JSONSerialization.data(withJSONObject: data),
                   let state = try? decoder.decode(RPCSessionState.self, from: stateData) {
                    currentState = state
                    if let callback = onStateChanged {
                        await MainActor.run { callback(state) }
                    }
                }
            }

        case "get_messages":
            logger.info("Received get_messages response")
            if let data = event.data?.dictValue {
                logger.info("get_messages data keys: \(data.keys.joined(separator: ", "))")
                if let messagesArray = data["messages"] as? [Any] {
                    logger.info("Found \(messagesArray.count) messages in response")
                    let messages = messagesArray.map { AnyCodable($0) }
                    if let callback = onMessagesLoaded {
                        await MainActor.run { callback(messages) }
                    }
                } else {
                    logger.warning("No 'messages' array in get_messages response")
                }
            } else {
                logger.warning("get_messages response has no data dict")
            }

        case "switch_session":
            // After switching, get the new session file from state
            if let callback = onSessionSwitched {
                let sessionFile = currentState?.sessionFile
                await MainActor.run { callback(sessionFile) }
            }
            // Automatically fetch state after switch
            try? await send(.getState)

        case "new_session":
            // After new session, fetch state to get the session file path
            try? await send(.getState)

        default:
            break
        }
    }

    private func handleTermination() async {
        isRunning = false
        process = nil

        if let callback = onProcessTerminated {
            await MainActor.run { callback() }
        }
    }
}

// MARK: - Errors

enum RPCError: Error {
    case notRunning
    case encodingFailed
    case commandFailed(String)
}

// MARK: - Convenience Callback Setup

extension PiRPCClient {
    func setCallbacks(
        onAgentStart: @escaping @MainActor () -> Void,
        onAgentEnd: @escaping @MainActor ([AnyCodable]) -> Void,
        onMessageUpdate: @escaping @MainActor (AnyCodable, AssistantMessageEvent) -> Void,
        onToolExecutionStart: @escaping @MainActor (String, String, [String: Any]) -> Void,
        onToolExecutionUpdate: @escaping @MainActor (String, String, AnyCodable?) -> Void,
        onToolExecutionEnd: @escaping @MainActor (String, String, AnyCodable?, Bool) -> Void,
        onStateChanged: @escaping @MainActor (RPCSessionState) -> Void,
        onError: @escaping @MainActor (String) -> Void,
        onProcessTerminated: @escaping @MainActor () -> Void,
        onMessagesLoaded: (@MainActor ([AnyCodable]) -> Void)? = nil,
        onSessionSwitched: (@MainActor (String?) -> Void)? = nil
    ) async {
        self.onAgentStart = onAgentStart
        self.onAgentEnd = onAgentEnd
        self.onMessageUpdate = onMessageUpdate
        self.onToolExecutionStart = onToolExecutionStart
        self.onToolExecutionUpdate = onToolExecutionUpdate
        self.onToolExecutionEnd = onToolExecutionEnd
        self.onStateChanged = onStateChanged
        self.onError = onError
        self.onProcessTerminated = onProcessTerminated
        self.onMessagesLoaded = onMessagesLoaded
        self.onSessionSwitched = onSessionSwitched
    }
}
