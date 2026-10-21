import Foundation

protocol LLMGeneratingProvider {
    var provider: LLMProvider { get }
    func responseStream(for request: LLMGenerateRequest, history: [ChatMessage]) async throws -> AsyncThrowingStream<LLMResponseEvent, Error>
}

enum LLMProviderError: LocalizedError {
    case invalidURL(String)
    case invalidResponse(String)
    case server(statusCode: Int, details: String)
    case missingAPIKey(String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let message),
             .invalidResponse(let message),
             .missingAPIKey(let message),
             .decodingFailed(let message):
            return message
        case .server(let statusCode, let details):
            return "请求失败：\(statusCode)\n\(details)"
        }
    }
}

enum LLMProviderFactory {
    static func makeProvider(for provider: LLMProvider) -> any LLMGeneratingProvider {
        switch provider {
        case .ollama:
            return OllamaProviderClient()
        case .deepseek:
            return DeepSeekProviderClient(contextBuilder: WebSearchContextBuilder())
        }
    }
}
