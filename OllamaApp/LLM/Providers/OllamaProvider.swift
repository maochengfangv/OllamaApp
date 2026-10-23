import Foundation

struct OllamaProviderClient: LLMGeneratingProvider {
    let provider: LLMProvider = .ollama

    private let baseURL = "http://127.0.0.1:11434/api/generate"

    private struct OllamaRequest: Codable {
        let model: String
        let prompt: String
        let stream: Bool
    }

    private struct OllamaResponse: Codable {
        let model: String
        let created_at: String
        let response: String
        let done: Bool
    }

    func responseStream(for request: AIRequest, context: LLMContextEnvelope) async throws -> AsyncThrowingStream<AIProviderChunk, Error> {
        guard let url = URL(string: baseURL) else {
            throw LLMProviderError.invalidURL("Ollama URL 不合法")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = request.timeoutInterval
        urlRequest.httpBody = try JSONEncoder().encode(
            OllamaRequest(model: request.model, prompt: makePrompt(from: request, context: context), stream: true)
        )

        return AsyncThrowingStream { continuation in
            let worker = Task {
                do {
                    let (result, response) = try await URLSession.shared.bytes(for: urlRequest)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw LLMProviderError.invalidResponse("Ollama 响应异常")
                    }

                    guard httpResponse.statusCode == 200 else {
                        var errorBody = ""
                        for try await line in result.lines {
                            errorBody += line + "\n"
                        }
                        throw LLMProviderError.server(
                            statusCode: httpResponse.statusCode,
                            details: errorBody.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }

                    for try await line in result.lines {
                        if Task.isCancelled { break }
                        guard let data = line.data(using: .utf8),
                              let decoded = try? JSONDecoder().decode(OllamaResponse.self, from: data) else {
                            continue
                        }
                        if !decoded.response.isEmpty {
                            continuation.yield(.delta(decoded.response))
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                worker.cancel()
            }
        }
    }

    private func makePrompt(from request: AIRequest, context: LLMContextEnvelope) -> String {
        var lines: [String] = []

        if let systemPrompt = request.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !systemPrompt.isEmpty {
            lines.append("System: \(systemPrompt)")
        }

        for systemMessage in context.systemMessages where !systemMessage.isEmpty {
            lines.append("System: \(systemMessage)")
        }

        for message in request.messages {
            let prefix: String
            switch message.role {
            case .system:
                prefix = "System"
            case .user:
                prefix = "User"
            case .assistant:
                prefix = "Assistant"
            }
            lines.append("\(prefix): \(message.content)")
        }

        lines.append("Assistant:")
        return lines.joined(separator: "\n\n")
    }
}
