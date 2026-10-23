import Foundation

struct ChatMessage: Identifiable, Equatable, Codable {
    var id = UUID()
    let role: MessageRole
    var content: String

    enum MessageRole: String, Codable {
        case user, model
    }
}

struct ChatSession: Identifiable, Codable, Equatable {
    var id: String
    var messages: [ChatMessage]
    var title: String
    var date: Date
}

enum AIMessageRole: String, Codable, Equatable {
    case system
    case user
    case assistant
}

struct AIMessage: Codable, Equatable {
    let role: AIMessageRole
    let content: String
}

enum LLMProvider: String, Codable, CaseIterable, Identifiable {
    case ollama
    case deepseek

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama:
            return "Ollama"
        case .deepseek:
            return "DeepSeek"
        }
    }

    var historyTitle: String {
        "\(displayName) History"
    }

    var newChatTitle: String {
        "New \(displayName) Chat"
    }

    var selectedModelKey: String {
        switch self {
        case .ollama:
            return "SelectedOllamaModel"
        case .deepseek:
            return "SelectedDeepSeekModel"
        }
    }

    var defaultModel: String {
        switch self {
        case .ollama:
            return "phi3"
        case .deepseek:
            return "deepseek-v4-flash"
        }
    }

    var modelPlaceholder: String {
        switch self {
        case .ollama:
            return "Model (e.g. llama3)"
        case .deepseek:
            return "Model (e.g. deepseek-v4-flash)"
        }
    }

    var accentColorName: String {
        switch self {
        case .ollama:
            return "blue"
        case .deepseek:
            return "green"
        }
    }

    var supportsWebEnhancement: Bool {
        self == .deepseek
    }
}

struct AIContextOptions: Codable, Equatable {
    let webEnabled: Bool

    static let disabled = AIContextOptions(webEnabled: false)
}

struct AIRetryPolicy: Codable, Equatable {
    let maxRetries: Int

    static let none = AIRetryPolicy(maxRetries: 0)
    static let `default` = AIRetryPolicy(maxRetries: 1)
}

struct AIRequest: Equatable {
    let requestID: UUID
    let sessionID: String?
    let preferredProvider: LLMProvider
    let fallbackProvider: LLMProvider?
    let model: String
    let messages: [AIMessage]
    let systemPrompt: String?
    let temperature: Double?
    let maxTokens: Int?
    let timeoutInterval: TimeInterval
    let contextOptions: AIContextOptions
    let retryPolicy: AIRetryPolicy
    let metadata: [String: String]

    init(
        requestID: UUID = UUID(),
        sessionID: String?,
        preferredProvider: LLMProvider,
        fallbackProvider: LLMProvider? = nil,
        model: String,
        messages: [AIMessage],
        systemPrompt: String? = "You are a helpful assistant.",
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        timeoutInterval: TimeInterval = 60,
        contextOptions: AIContextOptions = .disabled,
        retryPolicy: AIRetryPolicy = .default,
        metadata: [String: String] = [:]
    ) {
        self.requestID = requestID
        self.sessionID = sessionID
        self.preferredProvider = preferredProvider
        self.fallbackProvider = fallbackProvider
        self.model = model
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.timeoutInterval = timeoutInterval
        self.contextOptions = contextOptions
        self.retryPolicy = retryPolicy
        self.metadata = metadata
    }

    var latestUserMessage: String? {
        messages.last(where: { $0.role == .user })?.content
    }
}

struct AIUsage: Codable, Equatable {
    let inputCharacters: Int?
    let outputCharacters: Int
    let totalCharacters: Int?
    let estimatedCost: Double?

    static func estimated(from request: AIRequest, outputCharacters: Int) -> AIUsage {
        let inputCharacters = request.messages.reduce(0) { $0 + $1.content.count }
        let totalCharacters = inputCharacters + outputCharacters
        return AIUsage(
            inputCharacters: inputCharacters,
            outputCharacters: outputCharacters,
            totalCharacters: totalCharacters,
            estimatedCost: nil
        )
    }
}

struct AIResponseStart: Equatable {
    let requestID: UUID
    let provider: LLMProvider
    let model: String
}

struct AIResponseCompletion: Equatable {
    let requestID: UUID
    let provider: LLMProvider
    let model: String
    let durationMs: Int
    let firstTokenLatencyMs: Int?
    let retryCount: Int
    let fallbackUsed: Bool
    let usage: AIUsage
}

struct AIResponseCancellation: Equatable {
    let requestID: UUID
    let provider: LLMProvider
    let model: String
    let durationMs: Int
    let retryCount: Int
    let fallbackUsed: Bool
}

enum AIResponseEvent: Equatable {
    case started(AIResponseStart)
    case preview(String)
    case delta(String)
    case usage(AIUsage)
    case completed(AIResponseCompletion)
    case failed(AIClientError)
    case cancelled(AIResponseCancellation)
}

enum AIProviderChunk: Equatable {
    case preview(String)
    case delta(String)
    case usage(AIUsage)
}

extension ChatMessage.MessageRole {
    var aiRole: AIMessageRole {
        switch self {
        case .user:
            return .user
        case .model:
            return .assistant
        }
    }
}

extension ChatMessage {
    var aiMessage: AIMessage {
        AIMessage(role: role.aiRole, content: content)
    }
}
