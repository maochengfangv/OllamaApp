import Foundation

enum AIPromptTemplateID: String, Codable, Equatable, CaseIterable {
    case generalChat
    case engineeringChat
    case webResearch
    case requirementSummary
    case testCaseGeneration
    case conciseAssistant
}

enum AIPromptTemplateLibrary {
    static func render(id: AIPromptTemplateID, variables: [String: String] = [:]) -> String {
        let template = templateString(for: id)
        return variables.reduce(template) { partialResult, item in
            partialResult.replacingOccurrences(of: "{{\(item.key)}}", with: item.value)
        }
    }

    private static func templateString(for id: AIPromptTemplateID) -> String {
        switch id {
        case .generalChat:
            return "You are a helpful assistant."
        case .engineeringChat:
            return "You are a pragmatic senior software engineer. Give accurate, implementation-oriented answers, call out tradeoffs, and keep responses grounded in production constraints."
        case .webResearch:
            return "You are a research-oriented assistant. Synthesize online context carefully, distinguish facts from guesses, and include sources when web context is present."
        case .requirementSummary:
            return "You are a product and engineering assistant. Summarize requirements clearly, identify modules, APIs, edge cases, and delivery risks, and organize the answer for implementation."
        case .testCaseGeneration:
            return "You are a QA-minded engineering assistant. Generate structured test points, cover normal flow, edge cases, error handling, and regression risk."
        case .conciseAssistant:
            return "You are a concise assistant. Respond directly, keep answers brief, and prioritize actionable next steps."
        }
    }
}

enum AIPromptTemplateSelector {
    static func select(for prompt: String, webEnabled: Bool) -> AIPromptTemplateID {
        let normalized = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if webEnabled {
            return .webResearch
        }

        let requirementKeywords = ["需求", "prd", "product requirement", "接口草案", "模块设计", "方案设计"]
        if requirementKeywords.contains(where: normalized.contains) {
            return .requirementSummary
        }

        let testKeywords = ["测试点", "test case", "测试用例", "回归", "边界条件", "qa"]
        if testKeywords.contains(where: normalized.contains) {
            return .testCaseGeneration
        }

        return .engineeringChat
    }
}
