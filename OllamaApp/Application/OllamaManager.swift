import Foundation

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
