//
//  MemoryService.swift
//  OllamaApp
//
//  Created by maochengfang on 2026/10/28.
// 编排 Embedding + Store，提供 recall/remember

import Foundation

struct MemoryRecallResult {
    let context: String
    let hitCount: Int
    let preview: String
}

protocol MemoryServicing: AnyObject {
    func recallContext(query: String, topK: Int, minSimilarity: Float) async -> MemoryRecallResult?
    func remember(text: String) async
    func count() -> Int
    func items() -> [MemoryItem]
    func clearMemories()
}

extension MemoryServicing {
    func recallContext(query: String) async -> MemoryRecallResult? {
        await recallContext(query: query, topK: 4, minSimilarity: 0.35)
    }
}

final class MemoryService: MemoryServicing {
   
    static let shared = MemoryService()
    private let embedder: any LLMEmbeddingProviding
    private let store: any MemoryStoring
    
    init(embedder: any LLMEmbeddingProviding = GatewayEmbeddingProvider(), store: any MemoryStoring =  MemoryStore.shared) {
        self.embedder = embedder
        self.store = store
    }
    
    func recallContext(query: String, topK: Int = 4, minSimilarity: Float = 0.35) async -> MemoryRecallResult? {
        guard AIMemorySettings.isEnabled else { return nil }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let embedding = try? await embed(trimmed).first else { return nil }
        let matches = store.recall(embedding: embedding, topK: topK, minSimilarity: minSimilarity)
        guard let context = store.makeContextString(matches: matches) else { return nil }
        return MemoryRecallResult(
            context: context, hitCount: matches.count, preview: String(context.prefix(300))
        )
    }
    
    func remember(text: String) async {
        guard AIMemorySettings.isEnabled else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard shouldRemember(text: trimmed) else { return }
        guard let embedding = try? await embed(trimmed).first else { return }
        store.remember(text: trimmed, embedding: embedding, metadata: [:])
    }
    
    func count() -> Int {
        store.count()
    }

    func items() -> [MemoryItem] {
        store.allItems()
    }

    func clearMemories() {
        store.clear()
    }
    
    private func embed(_ text: String) async throws -> [[Float]] {
        let request = AIEmbeddingRequest(model: AIEmbeddingModel.configured, inputs: [text])
        let response = try await embedder.embeddings(for: request)
        return response.embeddings
    }

    private func shouldRemember(text: String) -> Bool {
        guard !text.isEmpty, text.count >= 6 else { return false }

        let normalized = text.lowercased()
        let questionMarkers = ["?", "？", "吗", "么", "嘛", "什么", "谁", "哪里", "哪儿", "为什么", "多少", "几", "如何", "怎么", "怎样"]
        if questionMarkers.contains(where: normalized.contains) {
            return false
        }

        let duplicates = store.allItems().contains {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == text
        }
        return !duplicates
    }
}
