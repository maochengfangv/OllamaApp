//
//  AIEvaluationModels.swift .swift
//  OllamaApp
//
//  Created by maochengfang on 2026/10/29.
//

import Foundation

struct AIEvaluationCase: Identifiable, Equatable {
    let id: String
    let title: String
    let prompt: String
    let webEnabled: Bool
    let promptOverrides: AIPromptOverrides
    let rules: [AIEvaluationRule]

    init(
        id: String,
        title: String,
        prompt: String,
        webEnabled: Bool = false,
        promptOverrides: AIPromptOverrides = .none,
        rules: [AIEvaluationRule]
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.webEnabled = webEnabled
        self.promptOverrides = promptOverrides
        self.rules = rules
    }
}

enum AIEvaluationRule: Equatable {
    case outputNotEmpty
    case outputContainsAny([String])
    case outputNotContainsAny([String])
    case memoryHitAtLeast(Int)
    case statusEquals(AIDebugStatus)
    case durationLessThan(Int)
}

struct AIEvaluationResult: Identifiable, Equatable {
    let id: String
    let title: String
    let outputPreview: String
    let status: AIDebugStatus
    let durationMs: Int?
    let memoryHitCount: Int?
    let usage: AIUsage?
    let failures: [String]
    let errorMessage: String?

    var isPassed: Bool {
        failures.isEmpty && status == .completed
    }
}

enum AIEvaluationLibrary {
    static let builtInCases: [AIEvaluationCase] = [
        AIEvaluationCase(
            id: "memory_name_recall",
            title: "Memory: 姓名召回",
            prompt: "我叫什么名字",
            rules: [
                .statusEquals(.completed),
                .memoryHitAtLeast(1),
                .outputContainsAny(["小芳"])
            ]
        ),
        AIEvaluationCase(
            id: "memory_location_recall",
            title: "Memory: 籍贯召回",
            prompt: "我是哪里人",
            rules: [
                .statusEquals(.completed),
                .memoryHitAtLeast(1),
                .outputContainsAny(["浙江"])
            ]
        ),
        AIEvaluationCase(
            id: "structured_output",
            title: "Prompt: 结构化输出",
            prompt: "请用 Markdown 列出 3 条 iOS 单元测试建议",
            rules: [
                .statusEquals(.completed),
                .outputNotEmpty,
                .outputContainsAny(["- ", "1.", "2."]),
                .durationLessThan(15000)
            ]
        )
    ]
}
