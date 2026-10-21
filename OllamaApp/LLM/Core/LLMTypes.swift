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

struct LLMGenerateRequest {
    let prompt: String
    let model: String
    let webEnabled: Bool
}

enum LLMResponseEvent {
    case preview(String)
    case delta(String)
}
