//
//  EmbeddingProvider.swift
//  OllamaApp
//
//  Created by maochengfang on 2026/10/28.
// OpenAI 兼容 /embeddings 网关 Provider（显式 8s 超时）

import Foundation

enum AIEmbeddingModel {
    static let defaultModel = "text-embedding-3-small"
    
    static var configured: String {
        if let stored = UserDefaults.standard.string(forKey: "EmbeddingModel")?.trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty {
            return stored
        }
        
        return defaultModel
    }
}

protocol LLMEmbeddingProviding {
    var provider: LLMProvider { get }
    func embeddings(for request: AIEmbeddingRequest) async throws -> AIEmbeddingResponse
}

struct OpenAICompatibleEmbeddingProvider: LLMEmbeddingProviding {
    let provider: LLMProvider = .deepseek

    private let baseURLKey = "DeepSeekBaseURL"
    private let apiKeyAccount = "deepseek_api_key"

    private struct RequestBody: Encodable {
        let model: String
        let input: [String]
    }

    private struct ResponseBody: Decodable {
        struct Item: Decodable {
            let embedding: [Float]
        }
        let data: [Item]
    }

    func embeddings(for request: AIEmbeddingRequest) async throws -> AIEmbeddingResponse {
        let apiKey = KeychainStore.shared.get(
            service: Bundle.main.bundleIdentifier ?? "OllamaApp",
            account: apiKeyAccount
        )
        guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMProviderError.missingAPIKey("Embedding 需要 API Key，请先在设置中配置。")
        }

        let base = (UserDefaults.standard.string(forKey: baseURLKey) ?? "https://api.deepseek.com")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/embeddings") else {
            throw LLMProviderError.invalidURL("Embedding Base URL 不合法：\(base)")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = request.timeoutInterval
        urlRequest.httpBody = try JSONEncoder().encode(RequestBody(model: request.model, input: request.inputs))

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse("Embedding 响应异常")
        }
        guard httpResponse.statusCode == 200 else {
            let details = String(data: data, encoding: .utf8) ?? ""
            throw LLMProviderError.server(statusCode: httpResponse.statusCode, details: details)
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        return AIEmbeddingResponse(
            embeddings: decoded.data.map(\.embedding),
            model: request.model,
            requestID: request.requestID
        )
    }
}
