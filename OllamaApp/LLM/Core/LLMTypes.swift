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

enum AICapability: String, Codable, Equatable, CaseIterable {
    case streaming
    case webSearch
    case reasoning
}

struct AIProviderCapabilities: Equatable {
    let supported: Set<AICapability>

    func supports(_ capability: AICapability) -> Bool {
        supported.contains(capability)
    }

    func supports(all required: [AICapability]) -> Bool {
        required.allSatisfy { supported.contains($0) }
    }
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

    var capabilities: AIProviderCapabilities {
        switch self {
        case .ollama:
            return AIProviderCapabilities(supported: [.streaming])
        case .deepseek:
            return AIProviderCapabilities(supported: [.webSearch, .reasoning])
        }
    }
}

enum AIRoutePolicy: Equatable {
    case direct(primary: LLMProvider, fallback: LLMProvider?)
    case capabilityPreferred(preferred: LLMProvider, fallback: LLMProvider?, required: [AICapability])

    func resolveRoutes(from allProviders: [LLMProvider]) -> [LLMProvider] {
        switch self {
        case .direct(let primary, let fallback):
            return compactUniqueProviders([primary, fallback])
        case .capabilityPreferred(let preferred, let fallback, let required):
            let capabilityMatched = allProviders.filter { provider in
                provider.capabilities.supports(all: required)
            }

            if required.isEmpty {
                return compactUniqueProviders([preferred, fallback])
            }

            var routes = compactUniqueProviders([preferred].filter {
                $0.capabilities.supports(all: required)
            })

            if let fallback, fallback.capabilities.supports(all: required) {
                routes = compactUniqueProviders(routes + [fallback])
            }

            routes = compactUniqueProviders(routes + capabilityMatched)
            return routes
        }
    }

    var primaryProvider: LLMProvider {
        switch self {
        case .direct(let primary, _):
            return primary
        case .capabilityPreferred(let preferred, _, _):
            return preferred
        }
    }

    var configuredFallbackProvider: LLMProvider? {
        switch self {
        case .direct(_, let fallback):
            return fallback
        case .capabilityPreferred(_, let fallback, _):
            return fallback
        }
    }
}

private func compactUniqueProviders(_ providers: [LLMProvider?]) -> [LLMProvider] {
    var seen = Set<LLMProvider>()
    var result: [LLMProvider] = []

    for provider in providers {
        guard let provider, !seen.contains(provider) else { continue }
        seen.insert(provider)
        result.append(provider)
    }
    return result
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
    let routePolicy: AIRoutePolicy
    let model: String
    let messages: [AIMessage]
    let systemPrompt: String?
    let promptTemplateID: AIPromptTemplateID
    let promptScene: AIPromptScene
    let promptModule: String
    let outputFormat: AIPromptOutputFormat
    let promptVariables: [String: String]
    let temperature: Double?
    let maxTokens: Int?
    let timeoutInterval: TimeInterval
    let contextOptions: AIContextOptions
    let retryPolicy: AIRetryPolicy
    let metadata: [String: String]

    init(
        requestID: UUID = UUID(),
        sessionID: String?,
        routePolicy: AIRoutePolicy,
        model: String,
        messages: [AIMessage],
        systemPrompt: String? = nil,
        promptTemplateID: AIPromptTemplateID = .generalChat,
        promptScene: AIPromptScene = .chat,
        promptModule: String = "general",
        outputFormat: AIPromptOutputFormat = .paragraph,
        promptVariables: [String: String] = [:],
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        timeoutInterval: TimeInterval = 60,
        contextOptions: AIContextOptions = .disabled,
        retryPolicy: AIRetryPolicy = .default,
        metadata: [String: String] = [:]
    ) {
        self.requestID = requestID
        self.sessionID = sessionID
        self.routePolicy = routePolicy
        self.model = model
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.promptTemplateID = promptTemplateID
        self.promptScene = promptScene
        self.promptModule = promptModule
        self.outputFormat = outputFormat
        self.promptVariables = promptVariables
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

    var preferredProvider: LLMProvider {
        routePolicy.primaryProvider
    }

    var fallbackProvider: LLMProvider? {
        routePolicy.configuredFallbackProvider
    }

    var resolvedSystemPrompt: String {
        if let systemPrompt, !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return systemPrompt
        }
        let mergedVariables = [
            "scene": promptScene.displayName,
            "module": promptModule,
            "output_format": outputFormat.displayName
        ].merging(promptVariables) { _, new in new }
        return AIPromptTemplateLibrary.render(id: promptTemplateID, variables: mergedVariables)
    }
}

struct AIUsage: Codable, Equatable {
    let inputCharacters: Int?
    let outputCharacters: Int
    let totalCharacters: Int?
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let estimatedCost: Double?

    static func estimated(from request: AIRequest, provider: LLMProvider, outputCharacters: Int) -> AIUsage {
        let inputCharacters = request.messages.reduce(0) { $0 + $1.content.count }
        let totalCharacters = inputCharacters + outputCharacters
        let inputTokens = AITokenEstimator.estimateTokenCount(forCharacterCount: inputCharacters)
        let outputTokens = AITokenEstimator.estimateTokenCount(forCharacterCount: outputCharacters)
        let totalTokens = inputTokens + outputTokens
        return AIUsage(
            inputCharacters: inputCharacters,
            outputCharacters: outputCharacters,
            totalCharacters: totalCharacters,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            estimatedCost: AIUsageCostEstimator.estimateCost(
                provider: provider,
                model: request.model,
                inputTokens: inputTokens,
                outputTokens: outputTokens
            )
        )
    }
}

enum AITokenEstimator {
    static func estimateTokenCount(forCharacterCount characterCount: Int) -> Int {
        guard characterCount > 0 else { return 0 }
        return max(Int(ceil(Double(characterCount) / 4.0)), 1)
    }
}

struct AIModelPricing {
    let inputCostPerMillionTokens: Double
    let outputCostPerMillionTokens: Double
}

enum AIUsageCostEstimator {
    static func estimateCost(provider: LLMProvider, model: String, inputTokens: Int, outputTokens: Int) -> Double? {
        guard let pricing = pricing(for: provider, model: model) else { return nil }
        let inputCost = (Double(inputTokens) / 1_000_000.0) * pricing.inputCostPerMillionTokens
        let outputCost = (Double(outputTokens) / 1_000_000.0) * pricing.outputCostPerMillionTokens
        return inputCost + outputCost
    }

    private static func pricing(for provider: LLMProvider, model: String) -> AIModelPricing? {
        switch provider {
        case .ollama:
            return AIModelPricing(inputCostPerMillionTokens: 0, outputCostPerMillionTokens: 0)
        case .deepseek:
            let normalized = model.lowercased()
            if normalized.contains("flash") {
                // Rough local estimate for observability only; update when provider pricing changes.
                return AIModelPricing(inputCostPerMillionTokens: 0.10, outputCostPerMillionTokens: 0.28)
            }
            return AIModelPricing(inputCostPerMillionTokens: 0.27, outputCostPerMillionTokens: 1.10)
        }
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
