import Foundation

protocol LLMGeneratingProvider {
    var provider: LLMProvider { get }
    func responseStream(for request: AIRequest, context: LLMContextEnvelope) async throws -> AsyncThrowingStream<AIProviderChunk, Error>
}

enum AIClientErrorCode: String, Codable, Equatable {
    case network
    case timeout
    case cancelled
    case invalidRequest
    case invalidResponse
    case auth
    case rateLimit
    case server
    case decoding
    case unsupportedCapability
    case unknown
}

struct AIClientError: Error, LocalizedError, Equatable {
    let code: AIClientErrorCode
    let provider: LLMProvider?
    let message: String
    let statusCode: Int?

    var errorDescription: String? {
        message
    }

    static func normalize(_ error: Error, provider: LLMProvider? = nil) -> AIClientError {
        if let clientError = error as? AIClientError {
            return clientError
        }

        if let providerError = error as? LLMProviderError {
            return providerError.asClientError(provider: provider)
        }

        if error is CancellationError {
            return AIClientError(code: .cancelled, provider: provider, message: "请求已取消", statusCode: nil)
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return AIClientError(code: .timeout, provider: provider, message: "请求超时", statusCode: nil)
            case .userAuthenticationRequired, .userCancelledAuthentication:
                return AIClientError(code: .auth, provider: provider, message: "鉴权失败", statusCode: nil)
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost:
                return AIClientError(code: .network, provider: provider, message: "网络连接失败", statusCode: nil)
            default:
                return AIClientError(code: .network, provider: provider, message: urlError.localizedDescription, statusCode: nil)
            }
        }

        return AIClientError(code: .unknown, provider: provider, message: error.localizedDescription, statusCode: nil)
    }
}

enum LLMProviderError: LocalizedError {
    case invalidURL(String)
    case invalidResponse(String)
    case server(statusCode: Int, details: String)
    case missingAPIKey(String)
    case decodingFailed(String)
    case timeout(String)
    case unsupportedCapability(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let message),
             .invalidResponse(let message),
             .missingAPIKey(let message),
             .decodingFailed(let message),
             .timeout(let message),
             .unsupportedCapability(let message):
            return message
        case .server(let statusCode, let details):
            return "请求失败：\(statusCode)\n\(details)"
        }
    }

    func asClientError(provider: LLMProvider?) -> AIClientError {
        switch self {
        case .invalidURL(let message):
            return AIClientError(code: .invalidRequest, provider: provider, message: message, statusCode: nil)
        case .invalidResponse(let message):
            return AIClientError(code: .invalidResponse, provider: provider, message: message, statusCode: nil)
        case .server(let statusCode, let details):
            let code: AIClientErrorCode
            switch statusCode {
            case 401, 403:
                code = .auth
            case 429:
                code = .rateLimit
            default:
                code = .server
            }
            return AIClientError(code: code, provider: provider, message: "请求失败：\(statusCode)\n\(details)", statusCode: statusCode)
        case .missingAPIKey(let message):
            return AIClientError(code: .auth, provider: provider, message: message, statusCode: nil)
        case .decodingFailed(let message):
            return AIClientError(code: .decoding, provider: provider, message: message, statusCode: nil)
        case .timeout(let message):
            return AIClientError(code: .timeout, provider: provider, message: message, statusCode: nil)
        case .unsupportedCapability(let message):
            return AIClientError(code: .unsupportedCapability, provider: provider, message: message, statusCode: nil)
        }
    }
}

enum LLMProviderFactory {
    static func makeProvider(for provider: LLMProvider) -> any LLMGeneratingProvider {
        switch provider {
        case .ollama:
            return OllamaProviderClient()
        case .deepseek:
            return DeepSeekProviderClient()
        }
    }
}
