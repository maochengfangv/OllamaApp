import Foundation
import OSLog
import Security

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

protocol LLMGeneratingProvider {
    var provider: LLMProvider { get }
    func responseStream(for request: LLMGenerateRequest, history: [ChatMessage]) async throws -> AsyncThrowingStream<LLMResponseEvent, Error>
}

enum ChatTelemetryEvent: Equatable {
    case generationStarted(provider: LLMProvider, model: String, webEnabled: Bool, historyCount: Int)
    case generationCompleted(provider: LLMProvider, model: String, durationMs: Int, outputLength: Int)
    case generationCancelled(provider: LLMProvider, model: String, durationMs: Int, outputLength: Int)
    case generationFailed(provider: LLMProvider, model: String, durationMs: Int, message: String)
    case sessionLoaded(provider: LLMProvider, sessionId: String, messageCount: Int)
    case sessionDeleted(provider: LLMProvider, sessionId: String)
    case legacyHistoryMigrated(provider: LLMProvider, sessionCount: Int)

    var name: String {
        switch self {
        case .generationStarted: return "generation_started"
        case .generationCompleted: return "generation_completed"
        case .generationCancelled: return "generation_cancelled"
        case .generationFailed: return "generation_failed"
        case .sessionLoaded: return "session_loaded"
        case .sessionDeleted: return "session_deleted"
        case .legacyHistoryMigrated: return "legacy_history_migrated"
        }
    }

    var message: String {
        switch self {
        case .generationStarted(let provider, let model, let webEnabled, let historyCount):
            return "provider=\(provider.rawValue) model=\(model) webEnabled=\(webEnabled) historyCount=\(historyCount)"
        case .generationCompleted(let provider, let model, let durationMs, let outputLength):
            return "provider=\(provider.rawValue) model=\(model) durationMs=\(durationMs) outputLength=\(outputLength)"
        case .generationCancelled(let provider, let model, let durationMs, let outputLength):
            return "provider=\(provider.rawValue) model=\(model) durationMs=\(durationMs) outputLength=\(outputLength)"
        case .generationFailed(let provider, let model, let durationMs, let message):
            return "provider=\(provider.rawValue) model=\(model) durationMs=\(durationMs) error=\(message)"
        case .sessionLoaded(let provider, let sessionId, let messageCount):
            return "provider=\(provider.rawValue) sessionId=\(sessionId) messageCount=\(messageCount)"
        case .sessionDeleted(let provider, let sessionId):
            return "provider=\(provider.rawValue) sessionId=\(sessionId)"
        case .legacyHistoryMigrated(let provider, let sessionCount):
            return "provider=\(provider.rawValue) sessionCount=\(sessionCount)"
        }
    }
}

protocol ChatTelemetryRecording {
    func record(_ event: ChatTelemetryEvent)
}

final class ChatTelemetryRecorder: ChatTelemetryRecording {
    static let shared = ChatTelemetryRecorder()

    private let logger: Logger

    init(subsystem: String = Bundle.main.bundleIdentifier ?? "OllamaApp", category: String = "LLM") {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    func record(_ event: ChatTelemetryEvent) {
        logger.info("\(event.name, privacy: .public) \(event.message, privacy: .public)")
    }
}

struct ChatSessionIndexItem: Codable, Equatable {
    let id: String
    let title: String
    let date: Date
}

final class ChatSessionStore {
    private let provider: LLMProvider
    private let fileManager = FileManager.default
    private let legacyKeys: [String]
    private let userDefaults: UserDefaults
    private let rootDirectoryOverride: URL?
    private let telemetry: any ChatTelemetryRecording

    init(
        provider: LLMProvider,
        legacyKeys: [String],
        userDefaults: UserDefaults = .standard,
        rootDirectoryOverride: URL? = nil,
        telemetry: any ChatTelemetryRecording = ChatTelemetryRecorder.shared
    ) {
        self.provider = provider
        self.legacyKeys = legacyKeys
        self.userDefaults = userDefaults
        self.rootDirectoryOverride = rootDirectoryOverride
        self.telemetry = telemetry
    }

    func loadSessionSummaries() -> [ChatSession] {
        migrateLegacyHistoryIfNeeded()

        let items = loadIndexItems()
        return items.map {
            ChatSession(id: $0.id, messages: [], title: $0.title, date: $0.date)
        }
    }

    func loadSession(id: String) -> ChatSession? {
        let url = sessionFileURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ChatSession.self, from: data)
    }

    func saveSession(_ session: ChatSession) {
        ensureBaseDirectory()
        let url = sessionFileURL(for: session.id)
        do {
            let data = try JSONEncoder().encode(session)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save session \(session.id): \(error)")
        }
    }

    func deleteSession(id: String) {
        let url = sessionFileURL(for: id)
        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                print("Failed to delete session \(id): \(error)")
            }
        }
    }

    func saveIndex(from summaries: [ChatSession]) {
        ensureBaseDirectory()
        let items = summaries.map { ChatSessionIndexItem(id: $0.id, title: $0.title, date: $0.date) }
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: indexFileURL, options: .atomic)
        } catch {
            print("Failed to save session index: \(error)")
        }
    }

    private func migrateLegacyHistoryIfNeeded() {
        guard !fileManager.fileExists(atPath: indexFileURL.path) else { return }

        for key in legacyKeys {
            guard let data = userDefaults.data(forKey: key),
                  let sessions = try? JSONDecoder().decode([ChatSession].self, from: data),
                  !sessions.isEmpty else {
                continue
            }

            ensureBaseDirectory()
            for session in sessions {
                saveSession(session)
            }
            saveIndex(from: sessions.sorted(by: { $0.date > $1.date }))
            telemetry.record(.legacyHistoryMigrated(provider: provider, sessionCount: sessions.count))
            return
        }
    }

    private func loadIndexItems() -> [ChatSessionIndexItem] {
        ensureBaseDirectory()
        guard let data = try? Data(contentsOf: indexFileURL),
              let items = try? JSONDecoder().decode([ChatSessionIndexItem].self, from: data) else {
            return []
        }
        return items.sorted(by: { $0.date > $1.date })
    }

    private var baseDirectoryURL: URL {
        let root = rootDirectoryOverride ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return root
            .appendingPathComponent("ChatSessions", isDirectory: true)
            .appendingPathComponent(provider.rawValue, isDirectory: true)
    }

    private var indexFileURL: URL {
        baseDirectoryURL.appendingPathComponent("index.json")
    }

    private func sessionFileURL(for id: String) -> URL {
        baseDirectoryURL.appendingPathComponent("\(id).json")
    }

    private func ensureBaseDirectory() {
        guard !fileManager.fileExists(atPath: baseDirectoryURL.path) else { return }
        do {
            try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
        } catch {
            print("Failed to create chat session directory: \(error)")
        }
    }
}

private enum LLMProviderError: LocalizedError {
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

private enum LLMProviderFactory {
    static func makeProvider(for provider: LLMProvider) -> any LLMGeneratingProvider {
        switch provider {
        case .ollama:
            return OllamaProviderClient()
        case .deepseek:
            return DeepSeekProviderClient(contextBuilder: WebSearchContextBuilder())
        }
    }
}

@MainActor
class OllamaManager: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating: Bool = false
    @Published var chatHistory: [ChatSession] = []

    let provider: LLMProvider

    var currentSessionId: String?
    private let providerClient: any LLMGeneratingProvider
    private let sessionStore: ChatSessionStore
    private let telemetry: any ChatTelemetryRecording

    private var currentTask: Task<Void, Never>?
    private var currentGenerationID: UUID?

    init(
        provider: LLMProvider,
        providerClient: (any LLMGeneratingProvider)? = nil,
        sessionStore: ChatSessionStore? = nil,
        telemetry: any ChatTelemetryRecording = ChatTelemetryRecorder.shared
    ) {
        self.provider = provider
        self.telemetry = telemetry
        self.providerClient = providerClient ?? LLMProviderFactory.makeProvider(for: provider)
        self.sessionStore = sessionStore ?? ChatSessionStore(
            provider: provider,
            legacyKeys: provider == .ollama ? ["ChatHistory_ollama", "OllamaChatHistory"] : ["ChatHistory_\(provider.rawValue)"],
            telemetry: telemetry
        )
        loadHistory()
    }

    func startNewChat() {
        stopGenerating(invalidateGenerationState: true)
        messages = []
        currentSessionId = nil
    }

    func loadChat(session: ChatSession) {
        stopGenerating(invalidateGenerationState: true)
        let storedSession = sessionStore.loadSession(id: session.id) ?? session
        messages = storedSession.messages
        currentSessionId = storedSession.id
        telemetry.record(.sessionLoaded(provider: provider, sessionId: storedSession.id, messageCount: storedSession.messages.count))
    }

    private func loadHistory() {
        chatHistory = sessionStore.loadSessionSummaries()
    }

    func deleteHistory(at offsets: IndexSet) {
        let idsToDelete = offsets.compactMap { index in
            chatHistory.indices.contains(index) ? chatHistory[index].id : nil
        }
        chatHistory.remove(atOffsets: offsets)
        idsToDelete.forEach { sessionStore.deleteSession(id: $0) }
        idsToDelete.forEach { telemetry.record(.sessionDeleted(provider: provider, sessionId: $0)) }
        sessionStore.saveIndex(from: chatHistory)

        if let currentId = currentSessionId, !chatHistory.contains(where: { $0.id == currentId }) {
            startNewChat()
        }
    }

    private func updateCurrentSession() {
        guard !messages.isEmpty else { return }

        let title = messages.last(where: { $0.role == .user })?.content ?? "New Chat"
        let shortTitle = String(title.prefix(15)) + (title.count > 15 ? "..." : "")

        let sessionDate = Date()
        let sessionId: String
        if let currentSessionId {
            sessionId = currentSessionId
        } else {
            let newSessionId = UUID().uuidString
            currentSessionId = newSessionId
            sessionId = newSessionId
        }

        let fullSession = ChatSession(id: sessionId, messages: messages, title: shortTitle, date: sessionDate)
        sessionStore.saveSession(fullSession)

        let summary = makeSessionSummary(from: fullSession)
        chatHistory.removeAll(where: { $0.id == sessionId })
        chatHistory.insert(summary, at: 0)
        sessionStore.saveIndex(from: chatHistory)
    }

    func stopGenerating(invalidateGenerationState: Bool = false) {
        currentTask?.cancel()
        currentTask = nil
        if invalidateGenerationState {
            currentGenerationID = nil
        }
        isGenerating = false
        updateCurrentSession()
    }

    func resend(messageId: UUID, model: String, webEnabled: Bool = false) async {
        guard !isGenerating else { return }
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        guard messages[index].role == .user else { return }

        let trimmedPrompt = messages[index].content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        isGenerating = true
        messages = Array(messages.prefix(index + 1))
        messages.append(ChatMessage(role: .model, content: ""))

        let request = LLMGenerateRequest(prompt: trimmedPrompt, model: model, webEnabled: webEnabled)
        let history = Array(messages.dropLast())
        await performGeneration(request: request, history: history)
    }

    func generate(prompt: String, model: String, webEnabled: Bool = false) async {
        guard !isGenerating else { return }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        isGenerating = true
        messages.append(ChatMessage(role: .user, content: trimmedPrompt))
        messages.append(ChatMessage(role: .model, content: ""))

        let request = LLMGenerateRequest(prompt: trimmedPrompt, model: model, webEnabled: webEnabled)
        let history = Array(messages.dropLast())
        await performGeneration(request: request, history: history)
    }

    private func performGeneration(request: LLMGenerateRequest, history: [ChatMessage]) async {
        let startDate = Date()
        let generationID = UUID()
        currentGenerationID = generationID
        telemetry.record(.generationStarted(
            provider: provider,
            model: request.model,
            webEnabled: request.webEnabled,
            historyCount: history.count
        ))
        currentTask?.cancel()
        currentTask = Task {
            do {
                let stream = try await providerClient.responseStream(for: request, history: history)
                for try await event in stream {
                    if Task.isCancelled { break }
                    apply(event)
                }
                finishGeneration(
                    request: request,
                    startDate: startDate,
                    error: nil,
                    cancelled: Task.isCancelled,
                    generationID: generationID
                )
            } catch {
                finishGeneration(
                    request: request,
                    startDate: startDate,
                    error: error,
                    cancelled: Task.isCancelled,
                    generationID: generationID
                )
            }
        }

        await currentTask?.value
    }

    private func apply(_ event: LLMResponseEvent) {
        guard let lastIndex = messages.indices.last else { return }

        switch event {
        case .preview(let preview):
            let existing = messages[lastIndex].content.trimmingCharacters(in: .whitespacesAndNewlines)
            if existing.isEmpty {
                messages[lastIndex].content = preview
            } else {
                messages[lastIndex].content = preview + "\n\n" + existing
            }
        case .delta(let text):
            messages[lastIndex].content += text
        }
    }

    private func finishGeneration(request: LLMGenerateRequest, startDate: Date, error: Error?, cancelled: Bool, generationID: UUID) {
        let isActiveGeneration = currentGenerationID == generationID
        defer {
            if isActiveGeneration {
                isGenerating = false
                currentTask = nil
                currentGenerationID = nil
                updateCurrentSession()
            }
        }

        guard let lastIndex = messages.indices.last else { return }
        let durationMs = max(Int(Date().timeIntervalSince(startDate) * 1000), 0)
        let outputLength = messages[lastIndex].content.count
        if cancelled {
            telemetry.record(.generationCancelled(
                provider: provider,
                model: request.model,
                durationMs: durationMs,
                outputLength: outputLength
            ))
            guard isActiveGeneration else { return }
            messages[lastIndex].content += messages[lastIndex].content.isEmpty ? "[Stopped]" : "\n[Stopped]"
            return
        }

        guard let error else {
            telemetry.record(.generationCompleted(
                provider: provider,
                model: request.model,
                durationMs: durationMs,
                outputLength: outputLength
            ))
            return
        }
        print("Error: \(error)")
        telemetry.record(.generationFailed(
            provider: provider,
            model: request.model,
            durationMs: durationMs,
            message: error.localizedDescription
        ))
        guard isActiveGeneration else { return }
        messages[lastIndex].content = error.localizedDescription
    }

    private func makeSessionSummary(from session: ChatSession) -> ChatSession {
        ChatSession(id: session.id, messages: [], title: session.title, date: session.date)
    }
}

private struct OllamaProviderClient: LLMGeneratingProvider {
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

    func responseStream(for request: LLMGenerateRequest, history: [ChatMessage]) async throws -> AsyncThrowingStream<LLMResponseEvent, Error> {
        guard let url = URL(string: baseURL) else {
            throw LLMProviderError.invalidURL("Ollama URL 不合法")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(
            OllamaRequest(model: request.model, prompt: request.prompt, stream: true)
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
                        throw LLMProviderError.server(statusCode: httpResponse.statusCode, details: errorBody.trimmingCharacters(in: .whitespacesAndNewlines))
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
}

private struct DeepSeekProviderClient: LLMGeneratingProvider {
    let provider: LLMProvider = .deepseek
    let contextBuilder: any LLMContextBuilding

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

    func responseStream(for request: LLMGenerateRequest, history: [ChatMessage]) async throws -> AsyncThrowingStream<LLMResponseEvent, Error> {
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

        let context = try await contextBuilder.buildContext(for: request)

        var messages: [DeepSeekChatCompletionRequest.Message] = [
            .init(role: "system", content: "You are a helpful assistant.")
        ]
        messages.append(contentsOf: context.systemMessages.map { .init(role: "system", content: $0) })
        messages.append(contentsOf: history.compactMap { message in
            switch message.role {
            case .user:
                return .init(role: "user", content: message.content)
            case .model:
                guard !message.content.isEmpty else { return nil }
                return .init(role: "assistant", content: message.content)
            }
        })

        let body = DeepSeekChatCompletionRequest(
            model: request.model,
            messages: messages,
            thinking: .init(type: "enabled"),
            reasoning_effort: "high",
            stream: false
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
                        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                        urlRequest.httpBody = encodedBody

                        let (data, response) = try await URLSession.shared.data(for: urlRequest)
                        guard let httpResponse = response as? HTTPURLResponse else {
                            lastError = "DeepSeek 响应异常"
                            continue
                        }

                        if httpResponse.statusCode == 200 {
                            guard let decoded = try? JSONDecoder().decode(DeepSeekChatCompletionResponse.self, from: data),
                                  let content = decoded.choices.first?.message.content else {
                                throw LLMProviderError.decodingFailed("DeepSeek 响应解析失败")
                            }

                            let prefix = context.previewText == nil ? "" : "\n\n【回答】\n"
                            continuation.yield(.delta(prefix + content))
                            continuation.finish()
                            return
                        }

                        let errorBody = String(data: data, encoding: .utf8) ?? ""
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

private struct LLMContextEnvelope {
    let systemMessages: [String]
    let previewText: String?

    static let empty = LLMContextEnvelope(systemMessages: [], previewText: nil)
}

private protocol LLMContextBuilding {
    func buildContext(for request: LLMGenerateRequest) async throws -> LLMContextEnvelope
}

private struct WebSearchContextBuilder: LLMContextBuilding {
    func buildContext(for request: LLMGenerateRequest) async throws -> LLMContextEnvelope {
        guard request.webEnabled else { return .empty }

        if let weatherContext = try await fetchWeatherContext(query: request.prompt), !weatherContext.isEmpty {
            return LLMContextEnvelope(
                systemMessages: [
                    "You have access to the following real-time data. Use it to answer the user. Do not say you cannot access real-time information.\n\n\(weatherContext)"
                ],
                previewText: "【联网结果】\n" + String(weatherContext.prefix(1500))
            )
        }

        if let searchContext = try await fetchDuckDuckGoContext(query: request.prompt), !searchContext.isEmpty {
            return LLMContextEnvelope(
                systemMessages: [
                    "Web search results for: \(request.prompt)\n\(searchContext)\nUse the above information when it is relevant and cite URLs. Do not say you cannot browse."
                ],
                previewText: "【联网结果】\n" + String(searchContext.prefix(1500))
            )
        }

        return LLMContextEnvelope(
            systemMessages: [],
            previewText: "【联网结果】\n联网失败：未获取到可用结果（可能被网络限制或查询源无返回）"
        )
    }

    private struct DuckDuckGoInstantAnswer: Decodable {
        struct RelatedTopic: Decodable {
            let Text: String?
            let FirstURL: String?
            let Topics: [RelatedTopic]?
        }

        let AbstractText: String?
        let AbstractURL: String?
        let RelatedTopics: [RelatedTopic]?
    }

    private struct OpenMeteoGeocodingResponse: Decodable {
        struct Result: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let country: String?
            let admin1: String?
        }

        let results: [Result]?
    }

    private struct OpenMeteoForecastResponse: Decodable {
        struct Current: Decodable {
            let time: String
            let temperature_2m: Double?
            let apparent_temperature: Double?
            let relative_humidity_2m: Double?
            let wind_speed_10m: Double?
            let weather_code: Int?
        }

        let current: Current?
    }

    private func fetchDuckDuckGoContext(query: String) async throws -> String? {
        var components = URLComponents(string: "https://api.duckduckgo.com/")!
        components.queryItems = [
            .init(name: "q", value: query),
            .init(name: "format", value: "json"),
            .init(name: "no_html", value: "1"),
            .init(name: "skip_disambig", value: "1")
        ]

        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }

        let decoded = try JSONDecoder().decode(DuckDuckGoInstantAnswer.self, from: data)

        var lines: [String] = []
        if let abstract = decoded.AbstractText, !abstract.isEmpty {
            if let url = decoded.AbstractURL, !url.isEmpty {
                lines.append("Abstract: \(abstract) (\(url))")
            } else {
                lines.append("Abstract: \(abstract)")
            }
        }

        func flatten(_ items: [DuckDuckGoInstantAnswer.RelatedTopic]?) -> [DuckDuckGoInstantAnswer.RelatedTopic] {
            guard let items else { return [] }
            var out: [DuckDuckGoInstantAnswer.RelatedTopic] = []
            for item in items {
                if let topics = item.Topics, !topics.isEmpty {
                    out.append(contentsOf: flatten(topics))
                } else {
                    out.append(item)
                }
            }
            return out
        }

        let topics = flatten(decoded.RelatedTopics).compactMap { topic -> String? in
            guard let text = topic.Text, !text.isEmpty else { return nil }
            if let url = topic.FirstURL, !url.isEmpty {
                return "\(text) (\(url))"
            }
            return text
        }

        for (index, item) in topics.prefix(5).enumerated() {
            lines.append("\(index + 1). \(item)")
        }

        let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { return nil }
        return String(joined.prefix(1500))
    }

    private func fetchWeatherContext(query: String) async throws -> String? {
        guard let locationName = extractLocationForWeather(query: query) else { return nil }

        var geocode = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        geocode.queryItems = [
            .init(name: "name", value: locationName),
            .init(name: "count", value: "1"),
            .init(name: "language", value: "zh"),
            .init(name: "format", value: "json")
        ]

        guard let geocodeURL = geocode.url else { return nil }
        let (geocodeData, geocodeResponse) = try await URLSession.shared.data(from: geocodeURL)
        guard let geocodeHTTP = geocodeResponse as? HTTPURLResponse, geocodeHTTP.statusCode == 200 else { return nil }

        let geocodeDecoded = try JSONDecoder().decode(OpenMeteoGeocodingResponse.self, from: geocodeData)
        guard let place = geocodeDecoded.results?.first else { return nil }

        var forecast = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        forecast.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code"),
            .init(name: "timezone", value: "auto")
        ]

        guard let forecastURL = forecast.url else { return nil }
        let (forecastData, forecastResponse) = try await URLSession.shared.data(from: forecastURL)
        guard let forecastHTTP = forecastResponse as? HTTPURLResponse, forecastHTTP.statusCode == 200 else { return nil }

        let forecastDecoded = try JSONDecoder().decode(OpenMeteoForecastResponse.self, from: forecastData)
        guard let current = forecastDecoded.current else { return nil }

        let displayPlace: String = {
            var parts: [String] = [place.name]
            if let admin1 = place.admin1, !admin1.isEmpty, admin1 != place.name { parts.append(admin1) }
            if let country = place.country, !country.isEmpty { parts.append(country) }
            return parts.joined(separator: ", ")
        }()

        var lines: [String] = []
        lines.append("Realtime weather (联网模式) for: \(displayPlace)")
        lines.append("Time: \(current.time)")

        if let temperature = current.temperature_2m { lines.append("Temperature: \(String(format: "%.1f", temperature))°C") }
        if let apparentTemperature = current.apparent_temperature { lines.append("Feels like: \(String(format: "%.1f", apparentTemperature))°C") }
        if let humidity = current.relative_humidity_2m { lines.append("Humidity: \(Int(humidity))%") }
        if let wind = current.wind_speed_10m { lines.append("Wind: \(String(format: "%.1f", wind)) km/h") }
        if let code = current.weather_code { lines.append("Condition: \(openMeteoWeatherDescription(code: code)) (code \(code))") }

        lines.append("Source: https://open-meteo.com/ (geocoding-api.open-meteo.com, api.open-meteo.com)")
        return lines.joined(separator: "\n")
    }

    private func extractLocationForWeather(query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        let triggers: [String] = ["天气", "气温", "温度", "体感", "湿度", "风速", "weather", "temperature"]
        guard triggers.contains(where: { lower.contains($0.lowercased()) }) else { return nil }

        let markers: [String] = ["天气", "气温", "温度", "weather", "temperature"]
        var markerRange: Range<String.Index>?
        for marker in markers {
            if let range = trimmed.range(of: marker, options: [.backwards, .caseInsensitive]) {
                markerRange = range
                break
            }
        }

        if let markerRange {
            let before = trimmed[..<markerRange.lowerBound]
            var candidate = String(before).trimmingCharacters(in: .whitespacesAndNewlines)
            candidate = candidate.replacingOccurrences(of: "的", with: "")
            candidate = candidate.replacingOccurrences(of: "今天", with: "")
            candidate = candidate.replacingOccurrences(of: "今日", with: "")
            candidate = candidate.replacingOccurrences(of: "现在", with: "")
            candidate = candidate.replacingOccurrences(of: "实时", with: "")
            candidate = candidate.replacingOccurrences(of: "一下", with: "")
            candidate = candidate.replacingOccurrences(of: "查询", with: "")
            candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: " ，,。.!！？?、:：；;\"'“”‘’()（）[]【】"))

            if candidate.count > 8 {
                candidate = String(candidate.suffix(8))
            }

            candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.isEmpty { return nil }
            return candidate
        }

        return nil
    }

    private func openMeteoWeatherDescription(code: Int) -> String {
        switch code {
        case 0: return "晴朗"
        case 1, 2, 3: return "多云"
        case 45, 48: return "有雾"
        case 51, 53, 55, 56, 57: return "毛毛雨"
        case 61, 63, 65, 66, 67: return "下雨"
        case 71, 73, 75, 77: return "下雪"
        case 80, 81, 82: return "阵雨"
        case 95: return "雷暴"
        case 96, 99: return "雷暴伴冰雹"
        default: return "未知"
        }
    }
}

final class KeychainStore {
    static let shared = KeychainStore()

    func set(_ value: String, service: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data

        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
    }

    func get(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
