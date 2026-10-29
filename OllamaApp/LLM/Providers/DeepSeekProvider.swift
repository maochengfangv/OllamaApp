import Foundation

struct DeepSeekProviderClient: LLMGeneratingProvider {
    let provider: LLMProvider = .deepseek

    private let deepSeekBaseURLKey = "DeepSeekBaseURL"

    private struct DeepSeekChatCompletionRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
            var tool_call_id: String? = nil
            var tool_calls: [ToolCall]? = nil
        }

        struct ToolCall: Encodable {
            struct Function: Encodable {
                let name: String
                let arguments: String
            }
            let id: String
            let type: String
            let function: Function
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

    private struct DeepSeekToolCallDTO: Decodable {
        struct Function: Decodable {
            let name: String?
            let arguments: String?
        }
        let index: Int?
        let id: String?
        let function: Function?
    }

    private struct DeepSeekChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
                let reasoning_content: String?
                let tool_calls: [DeepSeekToolCallDTO]?
            }

            let message: Message
        }

        let choices: [Choice]
    }

    private struct DeepSeekChatCompletionStreamResponse: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
                let reasoning_content: String?
                let tool_calls: [DeepSeekToolCallDTO]?
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
                let calls = message.toolCalls?.map {
                    DeepSeekChatCompletionRequest.ToolCall(
                        id: $0.id,
                        type: "function",
                        function: .init(name: $0.name, arguments: $0.argumentsJSON)
                    )
                }
                guard !message.content.isEmpty || !(calls?.isEmpty ?? true) else { return nil }
                return .init(role: "assistant", content: message.content, tool_calls: calls)
            case .tool:
                return .init(role: "tool", content: message.content, tool_call_id: message.toolCallID)
            }
        })

        let encodedTools: [[String: Any]]? = request.tools.isEmpty ? nil : request.tools.map { tool in
            [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": (try? JSONSerialization.jsonObject(with: Data(tool.parametersJSONSchema.utf8))) ?? [:]
                ]
            ]
        }

        let body = DeepSeekChatCompletionRequest(
            model: request.model,
            messages: messages,
            thinking: request.tools.isEmpty ? .init(type: "enabled") : .init(type: "disabled"),
            reasoning_effort: request.tools.isEmpty ? "high" : nil,
            stream: true
        )
        var encodedBody = try JSONEncoder().encode(body)
        if let encodedTools,
           var json = try JSONSerialization.jsonObject(with: encodedBody) as? [String: Any] {
            json["tools"] = encodedTools
            json["tool_choice"] = "auto"
            encodedBody = try JSONSerialization.data(withJSONObject: json)
        }

        // Provider 拉 SSE：发起流式请求并逐 chunk yield，返回 AsyncThrowingStream 供 AIClient 包流。
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

                        // URLSession.bytes 支持流式读取，不等待完整响应体
                        let (result, response) = try await URLSession.shared.bytes(for: urlRequest)
                        guard let httpResponse = response as? HTTPURLResponse else {
                            lastError = "DeepSeek 响应异常"
                            continue
                        }

                        if httpResponse.statusCode == 200 {
                            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
                            if contentType.contains("text/event-stream") {
                                // SSE 分支：逐行消费 data: 行，边收边解析
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

    // 逐 chunk 解析：解析 SSE 行（data: {...}），将 delta 拆分为 reasoning / content / tool_calls 后 yield。
    private func consumeSSE<Lines: AsyncSequence>(
        from lines: Lines,
        previewText: String?,
        continuation: AsyncThrowingStream<AIProviderChunk, Error>.Continuation
    ) async throws where Lines.Element == String {
        var hasYieldedAnswerPrefix = false
        var toolCallAccumulator: [Int: (id: String, name: String, arguments: String)] = [:]

        for try await line in lines {
            if Task.isCancelled {
                throw CancellationError()
            }

            // 只处理 SSE 数据行，忽略事件名/空行等协议行
            let trimmed = line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.hasPrefix("data:") else { continue }

            let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            // [DONE] 为流结束标记
            if payload == "[DONE]" {
                break
            }

            guard let data = payload.data(using: String.Encoding.utf8),
                  let decoded = try? JSONDecoder().decode(DeepSeekChatCompletionStreamResponse.self, from: data),
                  let delta = decoded.choices.first?.delta else {
                continue
            }

            if let calls = delta.tool_calls {
                for call in calls {
                    let index = call.index ?? 0
                    var merged = toolCallAccumulator[index] ?? ("", "", "")
                    if let id = call.id, !id.isEmpty { merged.id = id }
                    if let name = call.function?.name, !name.isEmpty { merged.name = name }
                    if let arguments = call.function?.arguments { merged.arguments += arguments }
                    toolCallAccumulator[index] = merged
                }
            }

            if let reasoning = delta.reasoning_content, !reasoning.isEmpty {
                // 思维链内容单独走 .reasoning，与正文展示分离
                continuation.yield(.reasoning(reasoning))
            }

            guard let content = delta.content, !content.isEmpty else { continue }

            if !hasYieldedAnswerPrefix, previewText != nil {
                continuation.yield(.delta("\n\n【回答】\n"))
                hasYieldedAnswerPrefix = true
            }
            // 正文增量逐 chunk 交给上层回写
            continuation.yield(.delta(content))
        }

        if !toolCallAccumulator.isEmpty {
            let calls = toolCallAccumulator.keys.sorted().map { index in
                let merged = toolCallAccumulator[index]!
                return AIToolCall(id: merged.id, name: merged.name, argumentsJSON: merged.arguments.isEmpty ? "{}" : merged.arguments)
            }
            continuation.yield(.toolCalls(calls))
        }
    }

    private func consumeJSONFallback(
        data: Data,
        previewText: String?,
        continuation: AsyncThrowingStream<AIProviderChunk, Error>.Continuation
    ) throws {
        guard let decoded = try? JSONDecoder().decode(DeepSeekChatCompletionResponse.self, from: data) else {
            throw LLMProviderError.decodingFailed("DeepSeek 响应解析失败")
        }

        let prefix = previewText == nil ? "" : "\n\n【回答】\n"
        if let reasoning = decoded.choices.first?.message.reasoning_content, !reasoning.isEmpty {
            continuation.yield(.reasoning(reasoning))
        }
        if let content = decoded.choices.first?.message.content, !content.isEmpty {
            continuation.yield(.delta(prefix + content))
        }

        if let rawCalls = decoded.choices.first?.message.tool_calls, !rawCalls.isEmpty {
            let calls = rawCalls.enumerated().map { index, call in
                AIToolCall(
                    id: call.id ?? "call_\(index)",
                    name: call.function?.name ?? "",
                    argumentsJSON: call.function?.arguments ?? "{}"
                )
            }
            continuation.yield(.toolCalls(calls))
        }
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
