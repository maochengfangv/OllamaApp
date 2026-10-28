//
//  TodoTools.swift
//  OllamaApp
//
//  Created by maochengfang on 2026/10/27.
//
// TODO :能力层：工具Schema + 确定性分发

import Foundation

enum TodoToolRunner {

static let toolsJSON = #"""
    [
      {"type":"function","function":{"name":"add_todo","description":"新增一条待办事项","parameters":{"type":"object","properties":{"title":{"type":"string","description":"待办内容"}},"required":["title"]}}},
      {"type":"function","function":{"name":"list_todos","description":"列出待办事项清单","parameters":{"type":"object","properties":{"include_done":{"type":"boolean","description":"是否包含已完成项，默认 true"}}}}},
      {"type":"function","function":{"name":"complete_todo","description":"把某条待办标记为已完成","parameters":{"type":"object","properties":{"key":{"type":"string","description":"待办标题关键字或 id"}},"required":["key"]}}},
      {"type":"function","function":{"name":"delete_todo","description":"删除某条待办","parameters":{"type":"object","properties":{"key":{"type":"string","description":"待办标题关键字或 id"}},"required":["key"]}}}
    ]
    """#

    static var tools: [AIToolDefinition] {
        guard let data = toolsJSON.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array.compactMap { item in
            guard let function = item["function"] as? [String: Any],
                  let name = function["name"] as? String,
                  let description = function["description"] as? String,
                  let parameters = function["parameters"],
                  let paramData = try? JSONSerialization.data(withJSONObject: parameters),
                  let paramString = String(data: paramData, encoding: .utf8) else { return nil }
            return AIToolDefinition(name: name, description: description, parametersJSONSchema: paramString)
        }
    }

    static func run(name: String, argumentsJSON: String) -> String {
        let args = (try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8))) as? [String: Any] ?? [:]
        switch name {
        case "add_todo":
            let  title = (args["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {return "错误：title 不能为空 请重试"}
            return "已添加代办：\(TodoStore.shared.add(title: title).title)"
        case "list_todos":
            let includeDone = args["include_done"] as? Bool ?? true
            let items = TodoStore.shared.list(includeDone: includeDone)
            guard !items.isEmpty else { return "当前没有代办事项" }
            return items.map { "\($0.isDone ? "[x]" : "[ ]") \($0.title)" }.joined(separator: "\n")
        case "complete_todo":
            let key = args["key"] as? String ?? ""
            return TodoStore.shared.complete(key: key).map { "已完成： \($0.title)" } ?? "未找到匹配的代办\(key)"
        case "delete_todo":
            let key = args["key"] as? String ?? ""
            return TodoStore.shared.delete(key: key) ? "已删除：\(key)" : "未能找到匹配的待办：\(key)"
        default:
            return "未知工具\(name)"
        }
    }
}
