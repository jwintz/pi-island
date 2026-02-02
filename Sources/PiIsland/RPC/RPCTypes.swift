import Foundation

// MARK: - RPC Commands

/// Commands sent to Pi via stdin
enum RPCCommand: Encodable {
    case prompt(message: String, images: [ImageData]? = nil, streamingBehavior: StreamingBehavior? = nil)
    case steer(message: String)
    case followUp(message: String)
    case abort
    case getState
    case getMessages
    case getAvailableModels
    case setModel(provider: String, modelId: String)
    case cycleModel
    case setThinkingLevel(level: ThinkingLevel)
    case cycleThinkingLevel
    case compact(customInstructions: String? = nil)
    case setAutoCompaction(enabled: Bool)
    case newSession(parentSession: String? = nil)
    case switchSession(sessionPath: String)
    case bash(command: String)
    case abortBash
    case getSessionStats
    case getCommands

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .prompt(let message, let images, let behavior):
            try container.encode("prompt", forKey: .type)
            try container.encode(message, forKey: .message)
            try container.encodeIfPresent(images, forKey: .images)
            try container.encodeIfPresent(behavior?.rawValue, forKey: .streamingBehavior)

        case .steer(let message):
            try container.encode("steer", forKey: .type)
            try container.encode(message, forKey: .message)

        case .followUp(let message):
            try container.encode("follow_up", forKey: .type)
            try container.encode(message, forKey: .message)

        case .abort:
            try container.encode("abort", forKey: .type)

        case .getState:
            try container.encode("get_state", forKey: .type)

        case .getMessages:
            try container.encode("get_messages", forKey: .type)

        case .getAvailableModels:
            try container.encode("get_available_models", forKey: .type)

        case .setModel(let provider, let modelId):
            try container.encode("set_model", forKey: .type)
            try container.encode(provider, forKey: .provider)
            try container.encode(modelId, forKey: .modelId)

        case .cycleModel:
            try container.encode("cycle_model", forKey: .type)

        case .setThinkingLevel(let level):
            try container.encode("set_thinking_level", forKey: .type)
            try container.encode(level.rawValue, forKey: .level)

        case .cycleThinkingLevel:
            try container.encode("cycle_thinking_level", forKey: .type)

        case .compact(let instructions):
            try container.encode("compact", forKey: .type)
            try container.encodeIfPresent(instructions, forKey: .customInstructions)

        case .setAutoCompaction(let enabled):
            try container.encode("set_auto_compaction", forKey: .type)
            try container.encode(enabled, forKey: .enabled)

        case .newSession(let parent):
            try container.encode("new_session", forKey: .type)
            try container.encodeIfPresent(parent, forKey: .parentSession)

        case .switchSession(let path):
            try container.encode("switch_session", forKey: .type)
            try container.encode(path, forKey: .sessionPath)

        case .bash(let command):
            try container.encode("bash", forKey: .type)
            try container.encode(command, forKey: .command)

        case .abortBash:
            try container.encode("abort_bash", forKey: .type)

        case .getSessionStats:
            try container.encode("get_session_stats", forKey: .type)

        case .getCommands:
            try container.encode("get_commands", forKey: .type)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, message, images, streamingBehavior
        case provider, modelId, level, customInstructions
        case enabled, parentSession, sessionPath, command
    }
}

enum StreamingBehavior: String {
    case steer
    case followUp
}

enum ThinkingLevel: String, CaseIterable {
    case off, minimal, low, medium, high, xhigh
}

struct ImageData: Encodable {
    let type = "image"
    let source: ImageSource

    struct ImageSource: Encodable {
        let type: String  // "base64" or "url"
        let mediaType: String?
        let data: String?
        let url: String?
    }
}

// MARK: - RPC Events

/// Events received from Pi via stdout
struct RPCEvent: Decodable, Sendable {
    let type: String

    // Response fields (for command responses)
    let command: String?
    let success: Bool?
    let error: String?
    let data: AnyCodable?
    let id: String?

    // Event-specific fields
    let message: AnyCodable?
    let messages: [AnyCodable]?
    let assistantMessageEvent: AssistantMessageEvent?
    let toolCallId: String?
    let toolName: String?
    let args: [String: AnyCodable]?
    let result: AnyCodable?
    let partialResult: AnyCodable?
    let isError: Bool?
    let reason: String?
    let attempt: Int?
    let maxAttempts: Int?
    let delayMs: Int?
    let errorMessage: String?
    let finalError: String?
    let aborted: Bool?
    let willRetry: Bool?
    let extensionPath: String?
    let event: String?
}

struct AssistantMessageEvent: Decodable, Sendable {
    let type: String  // start, text_start, text_delta, text_end, thinking_*, toolcall_*, done, error
    let contentIndex: Int?
    let delta: String?
    let content: String?
    let thinking: String?
    let reason: String?
    let toolCall: ToolCallData?
    let partial: AnyCodable?
}

struct ToolCallData: Decodable, Sendable {
    let id: String
    let name: String
    let arguments: [String: AnyCodable]?
}

// MARK: - State Types

struct RPCSessionState: Decodable, Sendable {
    let model: RPCModel?
    let thinkingLevel: String?
    let isStreaming: Bool?
    let isCompacting: Bool?
    let steeringMode: String?
    let followUpMode: String?
    let sessionFile: String?
    let sessionId: String?
    let autoCompactionEnabled: Bool?
    let messageCount: Int?
    let pendingMessageCount: Int?
}

struct RPCModel: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String?
    let api: String?
    let provider: String
    let baseUrl: String?
    let reasoning: Bool?
    let contextWindow: Int?
    let maxTokens: Int?

    var displayName: String {
        name ?? id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(provider)
    }

    static func == (lhs: RPCModel, rhs: RPCModel) -> Bool {
        lhs.id == rhs.id && lhs.provider == rhs.provider
    }
}

struct RPCSessionStats: Decodable, Sendable {
    let sessionFile: String?
    let sessionId: String?
    let userMessages: Int?
    let assistantMessages: Int?
    let toolCalls: Int?
    let toolResults: Int?
    let totalMessages: Int?
    let tokens: RPCTokens?
    let cost: Double?
}

struct RPCTokens: Decodable, Sendable {
    let input: Int?
    let output: Int?
    let cacheRead: Int?
    let cacheWrite: Int?
    let total: Int?
}

// MARK: - AnyCodable (for dynamic JSON)

struct AnyCodable: Codable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }

    var stringValue: String? { value as? String }
    var intValue: Int? { value as? Int }
    var doubleValue: Double? { value as? Double }
    var boolValue: Bool? { value as? Bool }
    var arrayValue: [Any]? { value as? [Any] }
    var dictValue: [String: Any]? { value as? [String: Any] }
}

// MARK: - Session Types

// MARK: - Session Types

enum RPCPhase: Equatable, Sendable {
    case disconnected
    case starting
    case idle
    case thinking
    case executing
    case error(String)

    var displayText: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .starting: return "Starting..."
        case .idle: return "Idle"
        case .thinking: return "Thinking..."
        case .executing: return "Executing..."
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

struct RPCMessage: Identifiable, Equatable, Sendable {
    let id: String
    let role: RPCMessageRole
    var content: String?
    var toolName: String?
    var toolArgs: [String: AnyCodable]?
    var toolResult: String?
    var toolStatus: RPCToolStatus?
    let timestamp: Date

    static func == (lhs: RPCMessage, rhs: RPCMessage) -> Bool {
        lhs.id == rhs.id
    }

    var displayText: String {
        if let content = content {
            return content
        }
        if let toolName = toolName {
            return "\(toolName): \(toolArgsPreview)"
        }
        return ""
    }

    var toolArgsPreview: String {
        guard let args = toolArgs else { return "" }
        if let path = args["path"]?.stringValue {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        if let command = args["command"]?.stringValue {
            return String(command.prefix(50))
        }
        return ""
    }
}

enum RPCMessageRole: String, Sendable {
    case user
    case assistant
    case tool
}

struct RPCToolExecution: Equatable, Sendable {
    let id: String
    let name: String
    let args: [String: AnyCodable]
    var status: RPCToolStatus
    var partialOutput: String?
    var result: String?

    static func == (lhs: RPCToolExecution, rhs: RPCToolExecution) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status
    }
}

enum RPCToolStatus: String, Sendable {
    case running
    case success
    case error
}
