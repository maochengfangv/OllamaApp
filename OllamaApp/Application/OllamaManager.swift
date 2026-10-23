import Foundation

@MainActor
class OllamaManager: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating: Bool = false
    @Published var chatHistory: [ChatSession] = []
    @Published var latestUsage: AIUsage?

    let provider: LLMProvider

    var currentSessionId: String?
    private let aiClient: any AIClienting
    private let sessionStore: ChatSessionStore
    private let telemetry: any ChatTelemetryRecording

    private var currentTask: Task<Void, Never>?
    private var currentGenerationID: UUID?

    init(
        provider: LLMProvider,
        aiClient: (any AIClienting)? = nil,
        sessionStore: ChatSessionStore? = nil,
        telemetry: any ChatTelemetryRecording = ChatTelemetryRecorder.shared
    ) {
        self.provider = provider
        self.telemetry = telemetry
        self.aiClient = aiClient ?? AIClient(telemetry: telemetry)
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
        latestUsage = nil
    }

    func loadChat(session: ChatSession) {
        stopGenerating(invalidateGenerationState: true)
        let storedSession = sessionStore.loadSession(id: session.id) ?? session
        messages = storedSession.messages
        currentSessionId = storedSession.id
        latestUsage = nil
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
        latestUsage = nil
        messages = Array(messages.prefix(index + 1))
        messages.append(ChatMessage(role: .model, content: ""))

        await performGeneration(model: model, prompt: trimmedPrompt, webEnabled: webEnabled)
    }

    func generate(prompt: String, model: String, webEnabled: Bool = false) async {
        guard !isGenerating else { return }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        isGenerating = true
        latestUsage = nil
        messages.append(ChatMessage(role: .user, content: trimmedPrompt))
        messages.append(ChatMessage(role: .model, content: ""))

        await performGeneration(model: model, prompt: trimmedPrompt, webEnabled: webEnabled)
    }

    private func performGeneration(model: String, prompt: String, webEnabled: Bool) async {
        let request = makeRequest(model: model, prompt: prompt, webEnabled: webEnabled)
        let startDate = Date()
        let generationID = request.requestID
        currentGenerationID = generationID
        currentTask?.cancel()
        currentTask = Task {
            var outcome: GenerationOutcome = .completed(nil)
            let stream = aiClient.responseStream(for: request)
            for await event in stream {
                switch event {
                case .started:
                    break
                case .preview, .delta:
                    apply(event)
                case .usage(let usage):
                    latestUsage = usage
                case .completed(let completion):
                    latestUsage = completion.usage
                    outcome = .completed(completion)
                case .failed(let error):
                    outcome = .failed(error)
                case .cancelled(let cancellation):
                    outcome = .cancelled(cancellation)
                }
            }

            if Task.isCancelled, !outcome.isTerminalCancellation {
                outcome = .cancelled(nil)
            }
            finishGeneration(request: request, startDate: startDate, outcome: outcome, generationID: generationID)
        }

        await currentTask?.value
    }

    private func apply(_ event: AIResponseEvent) {
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
        case .started, .usage, .completed, .failed, .cancelled:
            break
        }
    }

    private func finishGeneration(request: AIRequest, startDate: Date, outcome: GenerationOutcome, generationID: UUID) {
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

        switch outcome {
        case .completed:
            return
        case .cancelled(let cancellation):
            if cancellation == nil {
                telemetry.record(.generationCancelled(
                    requestID: request.requestID,
                    provider: request.preferredProvider,
                    model: request.model,
                    durationMs: max(Int(Date().timeIntervalSince(startDate) * 1000), 0),
                    retryCount: 0,
                    fallbackUsed: false,
                    outputLength: messages[lastIndex].content.count
                ))
            }
            guard isActiveGeneration else { return }
            messages[lastIndex].content += messages[lastIndex].content.isEmpty ? "[Stopped]" : "\n[Stopped]"
        case .failed(let error):
            guard isActiveGeneration else { return }
            messages[lastIndex].content = error.localizedDescription
        }
    }

    private func makeSessionSummary(from session: ChatSession) -> ChatSession {
        ChatSession(id: session.id, messages: [], title: session.title, date: session.date)
    }

    private func makeRequest(model: String, prompt: String, webEnabled: Bool) -> AIRequest {
        let requiredCapabilities: [AICapability] = webEnabled ? [.webSearch] : []
        let promptTemplateID = AIPromptTemplateSelector.select(for: prompt, webEnabled: webEnabled)

        return AIRequest(
            sessionID: currentSessionId,
            routePolicy: .capabilityPreferred(
                preferred: provider,
                fallback: nil,
                required: requiredCapabilities
            ),
            model: model,
            messages: Array(messages.dropLast()).map(\.aiMessage),
            promptTemplateID: promptTemplateID,
            timeoutInterval: 60,
            contextOptions: AIContextOptions(webEnabled: webEnabled),
            retryPolicy: .default,
            metadata: [
                "entryProvider": provider.rawValue,
                "promptTemplateID": promptTemplateID.rawValue
            ]
        )
    }
}

private enum GenerationOutcome {
    case completed(AIResponseCompletion?)
    case failed(AIClientError)
    case cancelled(AIResponseCancellation?)

    var isTerminalCancellation: Bool {
        if case .cancelled = self {
            return true
        }
        return false
    }
}
