//
//  MemoryStore.swift
//  OllamaApp
//
//  Created by maochengfang on 2026/10/28.
// 本地 JSON 持久化 + 线程安全 top-k 召回 + 上限裁剪

import Foundation

protocol MemoryStoring: AnyObject {
    var maxItems: Int { get }
    func recall(embedding: [Float], topK: Int, minSimilarity: Float) -> [MemoryMatch]
    func remember(text: String, embedding:[Float], metadata: [String: String])
    func makeContextString(matches: [MemoryMatch]) -> String?
    func count() -> Int
    func clear()
}

final class MemoryStore: MemoryStoring {
    static let shared = MemoryStore()
    
    let maxItems: Int
    private var items: [MemoryItem] = []
    private var lock = NSLock()
    private let fileURL: URL?
    
    init(maxItems: Int = 200,  fileURL: URL? = nil) {
        self.maxItems = maxItems
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
    }
    
    private static func defaultFileURL() -> URL? {
        let fileManager = FileManager.default
        guard let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = root.appendingPathComponent("AIMemory", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("memories.json")
    }
    
    
    func recall(embedding: [Float], topK: Int, minSimilarity: Float) -> [MemoryMatch] {
        lock.lock()
        defer {lock.unlock()}
        guard !embedding.isEmpty else { return [] }

        return items
             .filter { $0.embedding.count == embedding.count }
             .map { MemoryMatch(item: $0, similarity: VectorMath.cosineSimilarity(embedding, $0.embedding)) }
             .filter { $0.similarity >= minSimilarity }
             .sorted { $0.similarity > $1.similarity }
             .prefix(topK)
             .map { $0 }
    }
    
    func remember(text: String, embedding:[Float], metadata: [String: String]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock()
        items.append(MemoryItem(text: trimmed, embedding: embedding, metadata: metadata))
        if items.count > maxItems {
            items.removeFirst(items.count - maxItems)
        }
        let snapshot = items
        lock.unlock()
        persist(snapshot)
    }
    
    
    func makeContextString(matches: [MemoryMatch]) -> String? {
        guard !matches.isEmpty else { return nil }
        let lines = matches.enumerated().map { index , match in "\(index + 1). \(match.item.text) (similarity \(String(format: "%.2f", match.similarity)))"
        }
        
        return "Relevant long-term memories about the user:\n" + lines.joined(separator: "\n")
    }
    
    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return items.count
    }
    
    func clear() {
        lock.lock()
        items.removeAll()
        lock.unlock()
        persist([])
    }
    
    private func load() {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([MemoryItem].self, from: data) else {
            return
        }
        items = decoded
    }
    
    
    private func persist(_ snapshot: [MemoryItem]) {
        guard let fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
