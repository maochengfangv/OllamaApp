//
//  TodoStore.swift
//  OllamaApp
//
//  Created by maochengfang on 2026/10/27.
//
// TODO :数据层 模型 + JSON 持久化 
import Foundation

struct TodoItem: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var isDone: Bool
    let createdAt: Date
}

final class TodoStore {
    static let shared = TodoStore()
    
    private var items: [TodoItem] = []
    private let fileURL: URL
    
    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("todos.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) {
            items = decoded
        }
    }
    
    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL,options: .atomic)
    }
    
    func add(title: String) -> TodoItem {
        let item = TodoItem(id: UUID().uuidString, title: title, isDone: false, createdAt: Date())
        items.append(item)
        persist()
        return item
    }
    
    func list(includeDone: Bool = true) -> [TodoItem] {
        includeDone ? items : items.filter { !$0.isDone }
    }
    
    func complete(key: String) -> TodoItem? {
        guard let index = matchIndex(key) else { return nil }
        items[index].isDone = true
        persist()
        return items[index]
    }

    @discardableResult
    func toggle(key: String) -> TodoItem? {
        guard let index = matchIndex(key) else { return nil }
        items[index].isDone.toggle()
        persist()
        return items[index]
    }
    
    func delete(key: String) -> Bool {
        guard let index = matchIndex(key) else { return false }
        items.remove(at: index)
        persist()
        return true
    }
    
    private func matchIndex(_ key: String) -> Int? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if let byId = items.firstIndex(where: { $0.id == trimmed }) { return byId }
        return items.firstIndex(where: { $0.title.contains(trimmed) })
    }
}

