import Foundation

@MainActor
class OllamaManager: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating: Bool = false
    @Published var chatHistory: [ChatSession] = []
    @Published var latestUsage: AIUsage?
    @Published var latestDebugSnapshot: AIDebugSnapshot?

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
            legacyKeys: ["ChatHistory_\(provider.rawValue)"],
            telemetry: telemetry
        )
        loadHistory()
    }

    func startNewChat() {
        stopGenerating(invalidateGenerationState: true)
        messages = []
        currentSessionId = nil
        latestUsage = nil
        latestDebugSnapshot = nil
    }

    func loadChat(session: ChatSession) {
        stopGenerating(invalidateGenerationState: true)
        let storedSession = sessionStore.loadSession(id: session.id) ?? session
        messages = storedSession.messages
        currentSessionId = storedSession.id
        latestUsage = nil
        latestDebugSnapshot = nil
        telemetry.record(.sessionLoaded(provider: provider, sessionId: storedSession.id, messageCount: storedSession.messages.count))
    }

    func loadChat(sessionID: String) {
        guard let session = chatHistory.first(where: { $0.id == sessionID }) ?? sessionStore.loadSession(id: sessionID) else {
            return
        }
        loadChat(session: session)
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

    func resend(
        messageId: UUID,
        model: String,
        webEnabled: Bool = false,
        promptOverrides: AIPromptOverrides = .none
    ) async {
        guard !isGenerating else { return }
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        guard messages[index].role == .user else { return }

        let trimmedPrompt = messages[index].content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        isGenerating = true
        latestUsage = nil
        messages = Array(messages.prefix(index + 1))
        messages.append(ChatMessage(role: .model, content: ""))

        await performGeneration(
            model: model,
            prompt: trimmedPrompt,
            webEnabled: webEnabled,
            promptOverrides: promptOverrides
        )
    }

    func generate(
        prompt: String,
        model: String,
        webEnabled: Bool = false,
        promptOverrides: AIPromptOverrides = .none
    ) async {
        guard !isGenerating else { return }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        isGenerating = true
        latestUsage = nil
        messages.append(ChatMessage(role: .user, content: trimmedPrompt))
        messages.append(ChatMessage(role: .model, content: ""))

        await performGeneration(
            model: model,
            prompt: trimmedPrompt,
            webEnabled: webEnabled,
            promptOverrides: promptOverrides
        )
    }

    private func performGeneration(
        model: String,
        prompt: String,
        webEnabled: Bool,
        promptOverrides: AIPromptOverrides
    ) async {
        let request = makeRequest(
            model: model,
            prompt: prompt,
            webEnabled: webEnabled,
            promptOverrides: promptOverrides
        )
        let startDate = Date()
        let generationID = request.requestID
        currentGenerationID = generationID
        latestDebugSnapshot = makeDebugSnapshot(for: request)
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
                    latestDebugSnapshot?.usage = usage
                    latestDebugSnapshot?.updatedAt = Date()
                case .toolCalls:
                    break
                case .completed(let completion):
                    latestUsage = completion.usage
                    apply(completion: completion)
                    outcome = .completed(completion)
                case .failed(let error):
                    apply(error: error)
                    outcome = .failed(error)
                case .cancelled(let cancellation):
                    apply(cancellation: cancellation)
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
        case .started, .usage, .toolCalls, .completed, .failed, .cancelled:
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
                latestDebugSnapshot?.status = .cancelled
                latestDebugSnapshot?.resolvedProvider = request.preferredProvider
                latestDebugSnapshot?.durationMs = max(Int(Date().timeIntervalSince(startDate) * 1000), 0)
                latestDebugSnapshot?.updatedAt = Date()
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

    private func makeRequest(
        model: String,
        prompt: String,
        webEnabled: Bool,
        promptOverrides: AIPromptOverrides
    ) -> AIRequest {
        let requiredCapabilities: [AICapability] = webEnabled ? [.webSearch] : []
        let promptConfiguration = AIPromptTemplateSelector.resolveConfiguration(
            for: prompt,
            webEnabled: webEnabled,
            overrides: promptOverrides
        )

        return AIRequest(
            sessionID: currentSessionId,
            routePolicy: .capabilityPreferred(
                preferred: provider,
                fallback: nil,
                required: requiredCapabilities
            ),
            model: model,
            messages: Array(messages.dropLast()).map(\.aiMessage),
            promptTemplateID: promptConfiguration.templateID,
            promptScene: promptConfiguration.scene,
            promptModule: promptConfiguration.module,
            outputFormat: promptConfiguration.outputFormat,
            promptVariables: promptConfiguration.variables,
            timeoutInterval: 60,
            contextOptions: AIContextOptions(webEnabled: webEnabled),
            retryPolicy: .default,
            metadata: [
                "entryProvider": provider.rawValue,
                "promptTemplateID": promptConfiguration.templateID.rawValue,
                "promptScene": promptConfiguration.scene.rawValue,
                "promptModule": promptConfiguration.module,
                "outputFormat": promptConfiguration.outputFormat.rawValue,
                "promptOverridesApplied": promptOverrides == .none ? "false" : "true"
            ]
        )
    }

    private func makeDebugSnapshot(for request: AIRequest) -> AIDebugSnapshot {
        AIDebugSnapshot(
            requestID: request.requestID,
            sessionID: request.sessionID,
            status: .generating,
            promptPreview: String((request.latestUserMessage ?? "").prefix(120)),
            entryProvider: provider,
            resolvedProvider: nil,
            fallbackProvider: request.fallbackProvider,
            routePolicySummary: routePolicySummary(for: request.routePolicy),
            model: request.model,
            promptTemplateID: request.promptTemplateID,
            promptScene: request.promptScene,
            promptModule: request.promptModule,
            outputFormat: request.outputFormat,
            webEnabled: request.contextOptions.webEnabled,
            retryLimit: request.retryPolicy.maxRetries,
            retryCount: 0,
            fallbackUsed: false,
            durationMs: nil,
            firstTokenLatencyMs: nil,
            usage: nil,
            errorCode: nil,
            errorMessage: nil,
            updatedAt: Date()
        )
    }

    private func apply(completion: AIResponseCompletion) {
        latestDebugSnapshot?.status = .completed
        latestDebugSnapshot?.resolvedProvider = completion.provider
        latestDebugSnapshot?.retryCount = completion.retryCount
        latestDebugSnapshot?.fallbackUsed = completion.fallbackUsed
        latestDebugSnapshot?.durationMs = completion.durationMs
        latestDebugSnapshot?.firstTokenLatencyMs = completion.firstTokenLatencyMs
        latestDebugSnapshot?.usage = completion.usage
        latestDebugSnapshot?.errorCode = nil
        latestDebugSnapshot?.errorMessage = nil
        latestDebugSnapshot?.updatedAt = Date()
    }

    private func apply(error: AIClientError) {
        latestDebugSnapshot?.status = .failed
        latestDebugSnapshot?.resolvedProvider = error.provider ?? latestDebugSnapshot?.resolvedProvider ?? provider
        latestDebugSnapshot?.errorCode = error.code
        latestDebugSnapshot?.errorMessage = error.message
        latestDebugSnapshot?.updatedAt = Date()
    }

    private func apply(cancellation: AIResponseCancellation) {
        latestDebugSnapshot?.status = .cancelled
        latestDebugSnapshot?.resolvedProvider = cancellation.provider
        latestDebugSnapshot?.retryCount = cancellation.retryCount
        latestDebugSnapshot?.fallbackUsed = cancellation.fallbackUsed
        latestDebugSnapshot?.durationMs = cancellation.durationMs
        latestDebugSnapshot?.updatedAt = Date()
    }

    private func routePolicySummary(for policy: AIRoutePolicy) -> String {
        switch policy {
        case .direct(let primary, let fallback):
            return "direct(primary: \(primary.rawValue), fallback: \(fallback?.rawValue ?? "none"))"
        case .capabilityPreferred(let preferred, let fallback, let required):
            let requiredText = required.map(\.rawValue).joined(separator: ", ")
            return "capabilityPreferred(preferred: \(preferred.rawValue), fallback: \(fallback?.rawValue ?? "none"), required: [\(requiredText)])"
        }
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
