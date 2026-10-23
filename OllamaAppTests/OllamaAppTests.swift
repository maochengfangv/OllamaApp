//
//  OllamaAppTests.swift
//  OllamaAppTests
//
//  Created by maochengfang on 2026/3/27.
//

import XCTest
@testable import OllamaApp

final class OllamaAppTests: XCTestCase {
    private var tempDirectory: URL!
    private var userDefaults: UserDefaults!
    private var userDefaultsSuiteName: String!
    private var telemetry: TelemetrySpy!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        userDefaultsSuiteName = "OllamaAppTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: userDefaultsSuiteName)
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
        telemetry = TelemetrySpy()
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        if let userDefaultsSuiteName {
            userDefaults?.removePersistentDomain(forName: userDefaultsSuiteName)
        }
        tempDirectory = nil
        userDefaults = nil
        userDefaultsSuiteName = nil
        telemetry = nil
    }

    func testChatSessionStorePersistsIndexAndFullSession() throws {
        let store = ChatSessionStore(
            provider: .ollama,
            legacyKeys: ["LegacyKey"],
            userDefaults: userDefaults,
            rootDirectoryOverride: tempDirectory,
            telemetry: telemetry
        )

        let session = ChatSession(
            id: "session-1",
            messages: [
                ChatMessage(role: .user, content: "Hello"),
                ChatMessage(role: .model, content: "Hi there")
            ],
            title: "Hello",
            date: Date()
        )

        store.saveSession(session)
        store.saveIndex(from: [ChatSession(id: session.id, messages: [], title: session.title, date: session.date)])

        let summaries = store.loadSessionSummaries()
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.title, "Hello")
        XCTAssertTrue(summaries.first?.messages.isEmpty == true)

        let loaded = store.loadSession(id: "session-1")
        XCTAssertEqual(loaded?.messages.count, 2)
        XCTAssertEqual(loaded?.messages.last?.content, "Hi there")

        store.deleteSession(id: "session-1")
        XCTAssertNil(store.loadSession(id: "session-1"))
    }

    func testChatSessionStoreMigratesLegacyHistory() throws {
        let legacySession = ChatSession(
            id: "legacy-1",
            messages: [
                ChatMessage(role: .user, content: "Legacy prompt"),
                ChatMessage(role: .model, content: "Legacy answer")
            ],
            title: "Legacy",
            date: Date()
        )
        let legacyKey = "ChatHistory_ollama"
        let data = try JSONEncoder().encode([legacySession])
        userDefaults.set(data, forKey: legacyKey)

        let store = ChatSessionStore(
            provider: .ollama,
            legacyKeys: [legacyKey],
            userDefaults: userDefaults,
            rootDirectoryOverride: tempDirectory,
            telemetry: telemetry
        )

        let summaries = store.loadSessionSummaries()
        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.id, "legacy-1")
        XCTAssertEqual(store.loadSession(id: "legacy-1")?.messages.count, 2)
        XCTAssertTrue(telemetry.events.contains(where: { event in
            if case .legacyHistoryMigrated(let provider, let count) = event {
                return provider == .ollama && count == 1
            }
            return false
        }))
    }

    @MainActor
    func testOllamaManagerGenerateRecordsTelemetry() async {
        let store = ChatSessionStore(
            provider: .ollama,
            legacyKeys: [],
            userDefaults: userDefaults,
            rootDirectoryOverride: tempDirectory,
            telemetry: telemetry
        )
        let manager = OllamaManager(
            provider: .ollama,
            aiClient: AIClient(
                providerFactory: { _ in StubProvider(provider: .ollama, events: [.delta("Hello from stub")]) },
                contextBuilder: EmptyContextBuilder(),
                telemetry: telemetry
            ),
            sessionStore: store,
            telemetry: telemetry
        )

        await manager.generate(prompt: "Test", model: "stub-model")

        XCTAssertEqual(manager.messages.count, 2)
        XCTAssertEqual(manager.messages.first?.content, "Test")
        XCTAssertEqual(manager.messages.last?.content, "Hello from stub")
        XCTAssertFalse(manager.isGenerating)
        XCTAssertEqual(manager.chatHistory.count, 1)

        XCTAssertTrue(telemetry.events.contains(where: { $0.name == "generation_started" }))
        XCTAssertTrue(telemetry.events.contains(where: { $0.name == "generation_completed" }))
    }

    @MainActor
    func testOllamaManagerStopGeneratingTransitionsToCancelledState() async {
        let store = ChatSessionStore(
            provider: .ollama,
            legacyKeys: [],
            userDefaults: userDefaults,
            rootDirectoryOverride: tempDirectory,
            telemetry: telemetry
        )
        let provider = PlannedProvider(
            provider: .ollama,
            plans: [
                .events([.delta("partial output")], stepDelayNanoseconds: 300_000_000)
            ]
        )
        let manager = OllamaManager(
            provider: .ollama,
            aiClient: AIClient(
                providerFactory: { _ in provider },
                contextBuilder: EmptyContextBuilder(),
                telemetry: telemetry
            ),
            sessionStore: store,
            telemetry: telemetry
        )

        let generationTask = Task {
            await manager.generate(prompt: "Stop me", model: "slow-model")
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(manager.isGenerating)

        manager.stopGenerating()
        await generationTask.value

        XCTAssertFalse(manager.isGenerating)
        XCTAssertEqual(manager.messages.count, 2)
        XCTAssertEqual(manager.messages.first?.content, "Stop me")
        XCTAssertTrue(manager.messages.last?.content.contains("[Stopped]") == true)
        XCTAssertEqual(manager.chatHistory.count, 1)
        XCTAssertTrue(telemetry.events.contains(where: { $0.name == "generation_cancelled" }))
    }

    @MainActor
    func testOllamaManagerRetryAfterFailureTransitionsBackToCompletedState() async throws {
        let store = ChatSessionStore(
            provider: .ollama,
            legacyKeys: [],
            userDefaults: userDefaults,
            rootDirectoryOverride: tempDirectory,
            telemetry: telemetry
        )
        let provider = PlannedProvider(
            provider: .ollama,
            plans: [
                .failure("Stub failure"),
                .failure("Stub failure"),
                .events([.delta("Retry succeeded")])
            ]
        )
        let manager = OllamaManager(
            provider: .ollama,
            aiClient: AIClient(
                providerFactory: { _ in provider },
                contextBuilder: EmptyContextBuilder(),
                telemetry: telemetry
            ),
            sessionStore: store,
            telemetry: telemetry
        )

        await manager.generate(prompt: "Retry prompt", model: "retry-model")

        XCTAssertFalse(manager.isGenerating)
        XCTAssertEqual(manager.messages.count, 2)
        XCTAssertEqual(manager.messages.last?.content, "Stub failure")
        XCTAssertTrue(telemetry.events.contains(where: { $0.name == "generation_failed" }))

        let userMessageId = try XCTUnwrap(manager.messages.first?.id)
        await manager.resend(messageId: userMessageId, model: "retry-model")

        XCTAssertFalse(manager.isGenerating)
        XCTAssertEqual(manager.messages.count, 2)
        XCTAssertEqual(manager.messages.first?.content, "Retry prompt")
        XCTAssertEqual(manager.messages.last?.content, "Retry succeeded")

        let startedCount = telemetry.events.filter { $0.name == "generation_started" }.count
        let completedCount = telemetry.events.filter { $0.name == "generation_completed" }.count
        let failedCount = telemetry.events.filter { $0.name == "generation_failed" }.count
        XCTAssertEqual(startedCount, 2)
        XCTAssertEqual(completedCount, 1)
        XCTAssertEqual(failedCount, 1)
    }

    @MainActor
    func testOllamaManagerSwitchSessionWhileGeneratingCancelsAndLoadsTargetSession() async throws {
        let store = ChatSessionStore(
            provider: .ollama,
            legacyKeys: [],
            userDefaults: userDefaults,
            rootDirectoryOverride: tempDirectory,
            telemetry: telemetry
        )
        let sessionA = ChatSession(
            id: "session-a",
            messages: [
                ChatMessage(role: .user, content: "Session A"),
                ChatMessage(role: .model, content: "Answer A")
            ],
            title: "Session A",
            date: Date()
        )
        let sessionB = ChatSession(
            id: "session-b",
            messages: [
                ChatMessage(role: .user, content: "Session B"),
                ChatMessage(role: .model, content: "Answer B")
            ],
            title: "Session B",
            date: Date().addingTimeInterval(1)
        )
        store.saveSession(sessionA)
        store.saveSession(sessionB)
        store.saveIndex(from: [
            ChatSession(id: sessionB.id, messages: [], title: sessionB.title, date: sessionB.date),
            ChatSession(id: sessionA.id, messages: [], title: sessionA.title, date: sessionA.date)
        ])

        let provider = PlannedProvider(
            provider: .ollama,
            plans: [
                .events([.delta("streaming")], stepDelayNanoseconds: 300_000_000)
            ]
        )
        let manager = OllamaManager(
            provider: .ollama,
            aiClient: AIClient(
                providerFactory: { _ in provider },
                contextBuilder: EmptyContextBuilder(),
                telemetry: telemetry
            ),
            sessionStore: store,
            telemetry: telemetry
        )

        let targetSession = try XCTUnwrap(manager.chatHistory.first(where: { $0.id == "session-b" }))

        let generationTask = Task {
            await manager.generate(prompt: "In flight", model: "switch-model")
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(manager.isGenerating)

        manager.loadChat(session: targetSession)
        await generationTask.value

        XCTAssertFalse(manager.isGenerating)
        XCTAssertEqual(manager.currentSessionId, "session-b")
        XCTAssertEqual(manager.messages.map(\.content), ["Session B", "Answer B"])
        XCTAssertTrue(telemetry.events.contains(where: { $0.name == "generation_cancelled" }))
        XCTAssertTrue(telemetry.events.contains(where: { event in
            if case .sessionLoaded(let provider, let sessionId, let messageCount) = event {
                return provider == .ollama && sessionId == "session-b" && messageCount == 2
            }
            return false
        }))
    }
}

private final class TelemetrySpy: ChatTelemetryRecording {
    private(set) var events: [ChatTelemetryEvent] = []

    func record(_ event: ChatTelemetryEvent) {
        events.append(event)
    }
}

private struct EmptyContextBuilder: LLMContextBuilding {
    func buildContext(for request: AIRequest) async throws -> LLMContextEnvelope {
        .empty
    }
}

private struct StubProvider: LLMGeneratingProvider {
    let provider: LLMProvider
    let events: [AIProviderChunk]

    func responseStream(for request: AIRequest, context: LLMContextEnvelope) async throws -> AsyncThrowingStream<AIProviderChunk, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

}

private struct TestProviderError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private enum ProviderPlan {
    case events([AIProviderChunk], stepDelayNanoseconds: UInt64 = 0)
    case failure(String, delayNanoseconds: UInt64 = 0)
}

private actor PlannedProvider: LLMGeneratingProvider {
    let provider: LLMProvider
    private var plans: [ProviderPlan]
    private var currentIndex: Int = 0

    init(provider: LLMProvider, plans: [ProviderPlan]) {
        self.provider = provider
        self.plans = plans
    }

    func responseStream(for request: AIRequest, context: LLMContextEnvelope) async throws -> AsyncThrowingStream<AIProviderChunk, Error> {
        let plan = nextPlan()

        return AsyncThrowingStream { continuation in
            let worker = Task {
                do {
                    switch plan {
                    case .events(let events, let stepDelayNanoseconds):
                        for event in events {
                            if stepDelayNanoseconds > 0 {
                                try await Task.sleep(nanoseconds: stepDelayNanoseconds)
                            }
                            if Task.isCancelled { break }
                            continuation.yield(event)
                        }
                        continuation.finish()
                    case .failure(let message, let delayNanoseconds):
                        if delayNanoseconds > 0 {
                            try await Task.sleep(nanoseconds: delayNanoseconds)
                        }
                        throw TestProviderError(message: message)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                worker.cancel()
            }
        }
    }

    private func nextPlan() -> ProviderPlan {
        guard !plans.isEmpty else {
            return .events([])
        }

        let index = min(currentIndex, plans.count - 1)
        currentIndex += 1
        return plans[index]
    }
}
