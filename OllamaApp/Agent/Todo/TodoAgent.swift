//
//  TodoAgent.swift
//  OllamaApp
//
//  Created by maochengfang on 2026/10/27.
//
// TODO :编排层： ReAct循环 + DeepSeek调用
import Foundation
@MainActor
final class TodoAgent {
   
    enum AgentError: LocalizedError {
        case missingKey
        case badURL
        case http(String)
        case maxStepsReached
        
        var errorDescription: String? {
            switch self {
            case .missingKey: return "DeepSeek API Key 未配置，请先在设置中填写。"
            case .badURL: return "DeepSeek Base URL 不合法。"
            case .http(let detail): return "DeepSeek 请求失败：\(detail)"
            case .maxStepsReached: return "任务步骤过多，已停止（可能陷入循环）。"
            }
        }
    }
    
    private let model = "deepseek-v4-flash"
    private let maxSteps = 5
    private var history: [[String: Any]] = []
    private let systemPrompt = """
      你是一个待办事项助手。你只能通过提供的工具来操作用户的待办清单，绝不凭空编造或臆测待办内容。
      当用户提出新增、查看、完成、删除待办的诉求时，调用对应工具；一次回复中可以并行调用多个工具。
      所有工具执行完成后，用简洁的中文向用户汇报最终结果。
     """
    func reset() { history = [] }
    
    func send(_ userInput: String) async throws -> String {
        
        let trimmd = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmd.isEmpty else { return "" }
        
        history.append(["role":"user","content": trimmd])
        
        for _ in 0..<maxSteps {
            let message = try await requestCompletion()
            
            if let toolCalls = message["tool_calls"] as? [[String:Any]], !toolCalls.isEmpty {
                var assistantMessage: [String: Any] = ["role": "assistant"]
                if let content = message["content"] as? String, !content.isEmpty {
                    assistantMessage["content"] = content
                }
                assistantMessage["tool_calls"] = toolCalls
                history.append(assistantMessage)
                
                for call in toolCalls {
                    
                    let function = call["function"] as? [String: Any] ?? [:]
                    let name = function["name"] as? String ?? ""
                    let arguments = function["arguments"] as? String ?? "{}"
                    let callID = call["id"] as? String ?? ""
                    let result = TodoToolRunner.run(name: name, argumentsJSON: arguments)
                    history.append(["role": "tool", "tool_call_id": callID, "content": result])
                }
                continue
            }
            
            let answer = message["content"] as? String ?? ""
            history.append(["role":"assistant", "content": answer])
            return answer
        }
        
        throw AgentError.maxStepsReached
    }
    
    private func requestCompletion() async throws -> [String: Any] {
        let service = Bundle.main.bundleIdentifier ?? "OllamaApp"
        guard let apiKey = KeychainStore.shared.get(service: service, account: "deepseek_api_key"),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError.missingKey
        }
        
        let base = (UserDefaults.standard.string(forKey: "DeepSeekBaseURL") ?? "https://api.deepseek.com").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: base + "/chat/completions") else { throw AgentError.badURL }
        
        let tools = try JSONSerialization.jsonObject(with: Data(TodoToolRunner.toolsJSON.utf8))
        let system: [String: Any] = ["role": "system", "content": systemPrompt]
        let body: [String: Any] = [
            "model": model,
            "messages": [system] + history,
            "tools": tools,
            "tool_choice": "auto",
            "thinking": ["type": "disabled"],
            "stream": false
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? "未知错误"
            throw AgentError.http(detail)
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let choices = json["choices"] as? [[String: Any]] ?? []
        return choices.first?["message"] as? [String: Any] ?? [:]
    }
    
}
