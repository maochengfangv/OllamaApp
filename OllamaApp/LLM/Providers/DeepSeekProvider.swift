import Foundation

struct DeepSeekProviderClient: LLMGeneratingProvider {
    let provider: LLMProvider = .deepseek

    private let deepSeekBaseURLKey = "DeepSeekBaseURL"

    private struct DeepSeekChatCompletionRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        struct Thinking: Encodable {
            let type: String
        }

        let model: String
        let messages: [Message]
        let thinking: Thinking?
        let reasoning_effort: String?
        let stream: Bool
    }

    private struct DeepSeekChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }

            let message: Message
        }

        let choices: [Choice]
    }

    private struct DeepSeekChatCompletionStreamResponse: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }

            let delta: Delta?
            let finish_reason: String?
        }

        let choices: [Choice]
    }

    func responseStream(for request: AIRequest, context: LLMContextEnvelope) async throws -> AsyncThrowingStream<AIProviderChunk, Error> {
        let apiKey = KeychainStore.shared.get(service: Bundle.main.bundleIdentifier ?? "OllamaApp", account: "deepseek_api_key")
        guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMProviderError.missingAPIKey("DeepSeek API Key 未配置。请在 DeepSeek 设置里填写后再试。")
        }

        let base = (UserDefaults.standard.string(forKey: deepSeekBaseURLKey) ?? "https://api.deepseek.com")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let urls = deepSeekChatCompletionsURLs(fromBase: base)
        guard !urls.isEmpty else {
            throw LLMProviderError.invalidURL("DeepSeek Base URL 不合法：\(base)")
        }

        var messages: [DeepSeekChatCompletionRequest.Message] = [
            .init(role: "system", content: request.resolvedSystemPrompt)
        ]
        messages.append(contentsOf: context.systemMessages.map { .init(role: "system", content: $0) })
        messages.append(contentsOf: request.messages.compactMap { message in
            switch message.role {
            case .system:
                return .init(role: "system", content: message.content)
            case .user:
                return .init(role: "user", content: message.content)
            case .assistant:
                guard !message.content.isEmpty else { return nil }
                return .init(role: "assistant", content: message.content)
            }
        })

        let body = DeepSeekChatCompletionRequest(
            model: request.model,
            messages: messages,
            thinking: .init(type: "enabled"),
            reasoning_effort: "high",
            stream: true
        )
        let encodedBody = try JSONEncoder().encode(body)

        return AsyncThrowingStream { continuation in
            let worker = Task {
                do {
                    if let previewText = context.previewText, !previewText.isEmpty {
                        continuation.yield(.preview(previewText))
                    }

                    var lastError: String?
                    for (index, url) in urls.enumerated() {
                        if Task.isCancelled { break }

                        var urlRequest = URLRequest(url: url)
                        urlRequest.httpMethod = "POST"
                        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                        urlRequest.timeoutInterval = request.timeoutInterval
                        urlRequest.httpBody = encodedBody

                        let (result, response) = try await URLSession.shared.bytes(for: urlRequest)
                        guard let httpResponse = response as? HTTPURLResponse else {
                            lastError = "DeepSeek 响应异常"
                            continue
                        }

                        if httpResponse.statusCode == 200 {
                            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
                            if contentType.contains("text/event-stream") {
                                try await consumeSSE(
                                    from: result.lines,
                                    previewText: context.previewText,
                                    continuation: continuation
                                )
                            } else {
                                let data = try await collectData(from: result)
                                try consumeJSONFallback(
                                    data: data,
                                    previewText: context.previewText,
                                    continuation: continuation
                                )
                            }
                            continuation.finish()
                            return
                        }

                        let errorBody = try await collectStringLines(from: result.lines)
                        lastError = "DeepSeek 请求失败：\(httpResponse.statusCode)\n\(errorBody)"

                        if httpResponse.statusCode == 404, index < urls.count - 1 {
                            continue
                        }

                        break
                    }

                    throw LLMProviderError.invalidResponse(lastError ?? "DeepSeek 请求失败")
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                worker.cancel()
            }
        }
    }

    private func consumeSSE<Lines: AsyncSequence>(
        from lines: Lines,
        previewText: String?,
        continuation: AsyncThrowingStream<AIProviderChunk, Error>.Continuation
    ) async throws where Lines.Element == String {
        var hasYieldedAnswerPrefix = false

        for try await line in lines {
            if Task.isCancelled {
                throw CancellationError()
            }

            let trimmed = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.hasPrefix("data:") else { continue }

            let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if payload == "[DONE]" {
                return
            }

            guard let data = payload.data(using: String.Encoding.utf8),
                  let decoded = try? JSONDecoder().decode(DeepSeekChatCompletionStreamResponse.self, from: data),
                  let content = decoded.choices.first?.delta?.content,
                  !content.isEmpty else {
                continue
            }

            if !hasYieldedAnswerPrefix, previewText != nil {
                continuation.yield(.delta("\n\n【回答】\n"))
                hasYieldedAnswerPrefix = true
            }
            continuation.yield(.delta(content))
        }
    }

    private func consumeJSONFallback(
        data: Data,
        previewText: String?,
        continuation: AsyncThrowingStream<AIProviderChunk, Error>.Continuation
    ) throws {
        guard let decoded = try? JSONDecoder().decode(DeepSeekChatCompletionResponse.self, from: data),
              let content = decoded.choices.first?.message.content else {
            throw LLMProviderError.decodingFailed("DeepSeek 响应解析失败")
        }

        let prefix = previewText == nil ? "" : "\n\n【回答】\n"
        continuation.yield(.delta(prefix + content))
    }

    private func collectData(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(contentsOf: [byte])
        }
        return data
    }

    private func collectStringLines<Lines: AsyncSequence>(from lines: Lines) async throws -> String where Lines.Element == String {
        var result = ""
        for try await line in lines {
            result += line + "\n"
        }
        return result.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    private func deepSeekChatCompletionsURLs(fromBase base: String) -> [URL] {
        var normalized = base
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }

        var bases: [String] = [normalized]
        if normalized.hasSuffix("/v1") {
            bases.append(String(normalized.dropLast(3)))
        } else {
            bases.append(normalized + "/v1")
        }

        var urls: [URL] = []
        for candidateBase in bases {
            if let url = URL(string: candidateBase + "/chat/completions") {
                urls.append(url)
            }
            if let url = URL(string: candidateBase + "/v1/chat/completions") {
                urls.append(url)
            }
        }

        var seen = Set<String>()
        return urls.filter { url in
            let key = url.absoluteString
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }
}
