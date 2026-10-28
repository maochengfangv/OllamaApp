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

    private let aiClient: any AIClienting

    init(aiClient: (any AIClienting)? = nil) {
        self.aiClient = aiClient ?? AIClient()
    }

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
    private var history: [AIMessage] = []
    private let systemPrompt = """
      你是一个待办事项助手。你只能通过提供的工具来操作用户的待办清单，绝不凭空编造或臆测待办内容。
      当用户提出新增、查看、完成、删除待办的诉求时，调用对应工具；一次回复中可以并行调用多个工具。
      所有工具执行完成后，用简洁的中文向用户汇报最终结果。
     """
    func reset() { history = [] }
    
    func send(_ userInput: String, onDelta: ((String) -> Void)? = nil) async throws -> String {
        
        let trimmd = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmd.isEmpty else { return "" }
        
        history.append(AIMessage(role: .user, content: trimmd))
        
        for _ in 0..<maxSteps {
            let result = try await requestCompletion(onDelta: onDelta)
            
            if !result.toolCalls.isEmpty {
                history.append(AIMessage(role: .assistant, content: result.content, toolCalls: result.toolCalls))
                
                for call in result.toolCalls {
                    let output = TodoToolRunner.run(name: call.name, argumentsJSON: call.argumentsJSON)
                    history.append(AIMessage(role: .tool, content: output, toolCallID: call.id))
                }
                continue
            }
            
            history.append(AIMessage(role: .assistant, content: result.content))
            return result.content
        }
        
        throw AgentError.maxStepsReached
    }
    
    private struct CompletionResult {
        var content: String
        var toolCalls: [AIToolCall]
    }

    private func requestCompletion(onDelta: ((String) -> Void)?) async throws -> CompletionResult {
        let request = AIRequest(
            sessionID: nil,
            routePolicy: .direct(primary: .deepseek, fallback: nil),
            model: model,
            messages: history,
            systemPrompt: systemPrompt,
            contextOptions: .disabled,
            metadata: ["module": "todo-agent"],
            tools: TodoToolRunner.tools
        )

        var content = ""
        var toolCalls: [AIToolCall] = []
        var failure: Error?

        for await event in aiClient.responseStream(for: request) {
            switch event {
            case .delta(let piece):
                content += piece
                onDelta?(piece)
            case .toolCalls(let calls):
                toolCalls = calls
            case .failed(let error):
                failure = AgentError.http(error.localizedDescription)
            default:
                break
            }
        }

        if let failure { throw failure }
        return CompletionResult(content: content, toolCalls: toolCalls)
    }
    
}
