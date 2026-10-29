import Foundation

protocol AIClienting {
    func responseStream(for request: AIRequest) -> AsyncStream<AIResponseEvent>
    func embeddings(for request: AIEmbeddingRequest) async throws -> AIEmbeddingResponse
}

final class AIClient: AIClienting {
    static let shared = AIClient()

    private let providerFactory: (LLMProvider) -> any LLMGeneratingProvider
    private let contextBuilder: any LLMContextBuilding
    private let telemetry: any ChatTelemetryRecording
    private let embeddingProvider: any LLMEmbeddingProviding

    init(
        providerFactory: @escaping (LLMProvider) -> any LLMGeneratingProvider = LLMProviderFactory.makeProvider(for:),
        contextBuilder: any LLMContextBuilding = MemoryContextBuilder(),
        telemetry: any ChatTelemetryRecording = ChatTelemetryRecorder.shared,
        embeddingProvider: any LLMEmbeddingProviding = OpenAICompatibleEmbeddingProvider()
    ) {
        self.providerFactory = providerFactory
        self.contextBuilder = contextBuilder
        self.telemetry = telemetry
        self.embeddingProvider = embeddingProvider
    }

    func embeddings(for request: AIEmbeddingRequest) async throws -> AIEmbeddingResponse {
        let startDate = Date()
        do {
            let response = try await embeddingProvider.embeddings(for: request)
            telemetry.record(.embeddingCompleted(
                requestID: request.requestID,
                provider: request.provider,
                model: request.model,
                durationMs: max(Int(Date().timeIntervalSince(startDate) * 1000), 0),
                inputCount: request.inputs.count,
                dimensions: response.embeddings.first?.count ?? 0
            ))
            return response
        } catch {
            let normalized = AIClientError.normalize(error, provider: request.provider)
            telemetry.record(.embeddingFailed(
                requestID: request.requestID,
                provider: request.provider,
                model: request.model,
                durationMs: max(Int(Date().timeIntervalSince(startDate) * 1000), 0),
                errorCode: normalized.code,
                message: normalized.message
            ))
            throw normalized
        }
    }

    func responseStream(for request: AIRequest) -> AsyncStream<AIResponseEvent> {
        AsyncStream { continuation in
            let worker = Task {
                let startDate = Date()
                let routes = routeSequence(for: request)
                guard let initialProvider = routes.first else {
                    let finalError = AIClientError(
                        code: .unsupportedCapability,
                        provider: request.preferredProvider,
                        message: "没有 Provider 能满足当前能力要求",
                        statusCode: nil
                    )
                    finishFailure(
                        request: request,
                        provider: request.preferredProvider,
                        error: finalError,
                        startDate: startDate,
                        retryCount: 0,
                        fallbackUsed: false,
                        continuation: continuation
                    )
                    return
                }
                var firstTokenLatencyMs: Int?
                var usage: AIUsage?
                var outputCharacters = 0
                var retryCount = 0
                var hasAttempted = false

                continuation.yield(.started(
                    AIResponseStart(
                        requestID: request.requestID,
                        provider: initialProvider,
                        model: request.model
                    )
                ))
                telemetry.record(.generationStarted(
                    requestID: request.requestID,
                    provider: initialProvider,
                    model: request.model,
                    webEnabled: request.contextOptions.webEnabled,
                    historyCount: request.messages.count,
                    timeoutMs: Int(request.timeoutInterval * 1000),
                    retryLimit: request.retryPolicy.maxRetries,
                    fallbackProvider: request.fallbackProvider
                ))

                let context: LLMContextEnvelope
                do {
                    context = try await contextBuilder.buildContext(for: request)
                } catch {
                    let normalized = AIClientError.normalize(error, provider: request.preferredProvider)
                    finishFailure(
                        request: request,
                        provider: request.preferredProvider,
                        error: normalized,
                        startDate: startDate,
                        retryCount: retryCount,
                        fallbackUsed: false,
                        continuation: continuation
                    )
                    return
                }
                
                if let memoryInfo = context.memoryInfo {
                    continuation.yield(.memoryContext(memoryInfo))
                }

                for (routeIndex, route) in routes.enumerated() {
                    let fallbackUsed = route != request.preferredProvider

                    for attemptIndex in 0...request.retryPolicy.maxRetries {
                        if Task.isCancelled {
                            finishCancellation(
                                request: request,
                                provider: route,
                                startDate: startDate,
                                retryCount: retryCount,
                                fallbackUsed: fallbackUsed,
                                outputLength: outputCharacters,
                                continuation: continuation
                            )
                            return
                        }

                        if hasAttempted {
                            retryCount += 1
                        }
                        hasAttempted = true

                        do {
                            let providerClient = providerFactory(route)
                            let stream = try await providerClient.responseStream(for: request, context: context)
                            for try await chunk in stream {
                                if Task.isCancelled {
                                    throw CancellationError()
                                }

                                if firstTokenLatencyMs == nil, chunk.isContentBearing {
                                    firstTokenLatencyMs = max(Int(Date().timeIntervalSince(startDate) * 1000), 0)
                                }

                                switch chunk {
                                case .preview(let preview):
                                    outputCharacters += preview.count
                                    continuation.yield(.preview(preview))
                                case .delta(let text):
                                    outputCharacters += text.count
                                    continuation.yield(.delta(text))
                                case .usage(let chunkUsage):
                                    usage = chunkUsage
                                    continuation.yield(.usage(chunkUsage))
                                case .toolCalls(let calls):
                                    continuation.yield(.toolCalls(calls))
                                case .reasoning(let text):
                                    outputCharacters += text.count
                                    continuation.yield(.reasoning(text))
                                }
                            }

                            let finalUsage = usage ?? AIUsage.estimated(from: request, provider: route, outputCharacters: outputCharacters)
                            if usage == nil {
                                continuation.yield(.usage(finalUsage))
                            }

                            let completion = AIResponseCompletion(
                                requestID: request.requestID,
                                provider: route,
                                model: request.model,
                                durationMs: max(Int(Date().timeIntervalSince(startDate) * 1000), 0),
                                firstTokenLatencyMs: firstTokenLatencyMs,
                                retryCount: retryCount,
                                fallbackUsed: fallbackUsed,
                                usage: finalUsage
                            )
                            telemetry.record(.generationCompleted(
                                requestID: request.requestID,
                                provider: route,
                                model: request.model,
                                durationMs: completion.durationMs,
                                firstTokenLatencyMs: completion.firstTokenLatencyMs,
                                retryCount: completion.retryCount,
                                fallbackUsed: completion.fallbackUsed,
                                inputTokens: finalUsage.inputTokens,
                                outputTokens: finalUsage.outputTokens,
                                totalTokens: finalUsage.totalTokens,
                                outputLength: finalUsage.outputCharacters,
                                estimatedCost: finalUsage.estimatedCost
                            ))
                            continuation.yield(.completed(completion))
                            continuation.finish()
                            return
                        } catch {
                            let normalized = AIClientError.normalize(error, provider: route)
                            if normalized.code == .cancelled {
                                finishCancellation(
                                    request: request,
                                    provider: route,
                                    startDate: startDate,
                                    retryCount: retryCount,
                                    fallbackUsed: fallbackUsed,
                                    outputLength: outputCharacters,
                                    continuation: continuation
                                )
                                return
                            }

                            if shouldRetry(error: normalized), attemptIndex < request.retryPolicy.maxRetries {
                                continue
                            }

                            let hasNextRoute = routeIndex < routes.count - 1
                            if fallbackUsed || !hasNextRoute {
                                finishFailure(
                                    request: request,
                                    provider: route,
                                    error: normalized,
                                    startDate: startDate,
                                    retryCount: retryCount,
                                    fallbackUsed: fallbackUsed,
                                    continuation: continuation
                                )
                                return
                            }

                            break
                        }
                    }
                }

                let finalError = AIClientError(
                    code: .unknown,
                    provider: request.preferredProvider,
                    message: "未找到可用的 Provider",
                    statusCode: nil
                )
                finishFailure(
                    request: request,
                    provider: request.preferredProvider,
                    error: finalError,
                    startDate: startDate,
                    retryCount: retryCount,
                    fallbackUsed: false,
                    continuation: continuation
                )
            }

            continuation.onTermination = { _ in
                worker.cancel()
            }
        }
    }

    private func routeSequence(for request: AIRequest) -> [LLMProvider] {
        request.routePolicy.resolveRoutes(from: LLMProvider.allCases)
    }

    private func shouldRetry(error: AIClientError) -> Bool {
        switch error.code {
        case .auth, .invalidRequest, .unsupportedCapability, .cancelled:
            return false
        default:
            return true
        }
    }

    private func finishFailure(
        request: AIRequest,
        provider: LLMProvider,
        error: AIClientError,
        startDate: Date,
        retryCount: Int,
        fallbackUsed: Bool,
        continuation: AsyncStream<AIResponseEvent>.Continuation
    ) {
        let durationMs = max(Int(Date().timeIntervalSince(startDate) * 1000), 0)
        telemetry.record(.generationFailed(
            requestID: request.requestID,
            provider: provider,
            model: request.model,
            durationMs: durationMs,
            retryCount: retryCount,
            fallbackUsed: fallbackUsed,
            errorCode: error.code,
            message: error.message
        ))
        continuation.yield(.failed(error))
        continuation.finish()
    }

    private func finishCancellation(
        request: AIRequest,
        provider: LLMProvider,
        startDate: Date,
        retryCount: Int,
        fallbackUsed: Bool,
        outputLength: Int,
        continuation: AsyncStream<AIResponseEvent>.Continuation
    ) {
        let durationMs = max(Int(Date().timeIntervalSince(startDate) * 1000), 0)
        telemetry.record(.generationCancelled(
            requestID: request.requestID,
            provider: provider,
            model: request.model,
            durationMs: durationMs,
            retryCount: retryCount,
            fallbackUsed: fallbackUsed,
            outputLength: outputLength
        ))
        continuation.yield(.cancelled(
            AIResponseCancellation(
                requestID: request.requestID,
                provider: provider,
                model: request.model,
                durationMs: durationMs,
                retryCount: retryCount,
                fallbackUsed: fallbackUsed
            )
        ))
        continuation.finish()
    }
}

private extension AIProviderChunk {
    var isContentBearing: Bool {
        switch self {
        case .preview, .delta, .reasoning:
            return true
        case .usage, .toolCalls:
            return false
        }
    }
}
