//
//  MemoryContextBuilder.swift
//  OllamaApp
//
//  Created by maochengfang on 2026/10/28.
//  装饰器模式包裹 WebSearchContextBuilder，零侵入注入记忆

import Foundation

struct MemoryContextBuilder: LLMContextBuilding {
    private let base: any LLMContextBuilding
    private let memory: any MemoryServicing

    init(
        base: any LLMContextBuilding = WebSearchContextBuilder(),
        memory: any MemoryServicing = MemoryService.shared
    ) {
        self.base = base
        self.memory = memory
    }

    func buildContext(for request: AIRequest) async throws -> LLMContextEnvelope {
        let baseEnvelope = (try? await base.buildContext(for: request)) ?? .empty
        guard request.contextOptions.memoryEnabled else { return baseEnvelope }
        guard let query = request.latestUserMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty else {
            return baseEnvelope
        }
        guard let recalled = await memory.recallContext(query: query) else {
            return baseEnvelope
        }
        return LLMContextEnvelope(
            systemMessages: [recalled.context] + baseEnvelope.systemMessages,
            previewText: baseEnvelope.previewText,
            memoryInfo: AIMemoryContextInfo(hitCount: recalled.hitCount, preview: recalled.preview)
        )
    }
}

