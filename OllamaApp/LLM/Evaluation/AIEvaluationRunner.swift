//
//  AIEvaluationRunner.swift
//  OllamaApp
//
//  Created by maochengfang on 2026/10/29.
//

import Foundation

struct AIEvaluationRunner {
    private let aiClient: any AIClienting

    init(aiClient: any AIClienting = AIClient.shared) {
        self.aiClient = aiClient
    }

    func runBuiltInCases(provider: LLMProvider, model: String) async -> [AIEvaluationResult] {
        var results: [AIEvaluationResult] = []
        for evaluationCase in AIEvaluationLibrary.builtInCases {
            let result = await run(evaluationCase, provider: provider, model: model)
            results.append(result)
        }
        return results
    }

    func run(_ evaluationCase: AIEvaluationCase, provider: LLMProvider, model: String) async -> AIEvaluationResult {
        let request = makeRequest(for: evaluationCase, provider: provider, model: model)
        var output = ""
        var usage: AIUsage?
        var memoryHitCount: Int?
        var status: AIDebugStatus = .generating
        var durationMs: Int?
        var errorMessage: String?

        let stream = aiClient.responseStream(for: request)
        for await event in stream {
            switch event {
            case .started, .toolCalls, .reasoning:
                break
            case .preview(let preview):
                if output.isEmpty {
                    output = preview
                }
            case .delta(let text):
                output += text
            case .usage(let newUsage):
                usage = newUsage
            case .memoryContext(let info):
                memoryHitCount = info.hitCount
            case .completed(let completion):
                status = .completed
                durationMs = completion.durationMs
                usage = completion.usage
            case .failed(let error):
                status = .failed
                errorMessage = error.message
            case .cancelled(let cancellation):
                status = .cancelled
                durationMs = cancellation.durationMs
                errorMessage = "Evaluation cancelled"
            }
        }

        let failures = evaluate(
            rules: evaluationCase.rules,
            output: output,
            status: status,
            durationMs: durationMs,
            memoryHitCount: memoryHitCount
        )

        return AIEvaluationResult(
            id: evaluationCase.id,
            title: evaluationCase.title,
            outputPreview: String(output.prefix(160)),
            status: status,
            durationMs: durationMs,
            memoryHitCount: memoryHitCount,
            usage: usage,
            failures: failures,
            errorMessage: errorMessage
        )
    }

    private func makeRequest(for evaluationCase: AIEvaluationCase, provider: LLMProvider, model: String) -> AIRequest {
        let promptConfiguration = AIPromptTemplateSelector.resolveConfiguration(
            for: evaluationCase.prompt,
            webEnabled: evaluationCase.webEnabled,
            overrides: evaluationCase.promptOverrides
        )

        let requiredCapabilities: [AICapability] = evaluationCase.webEnabled ? [.webSearch] : []

        return AIRequest(
            sessionID: nil,
            routePolicy: .capabilityPreferred(
                preferred: provider,
                fallback: nil,
                required: requiredCapabilities
            ),
            model: model,
            messages: [AIMessage(role: .user, content: evaluationCase.prompt)],
            promptTemplateID: promptConfiguration.templateID,
            promptScene: promptConfiguration.scene,
            promptModule: promptConfiguration.module,
            outputFormat: promptConfiguration.outputFormat,
            promptVariables: promptConfiguration.variables,
            timeoutInterval: 60,
            contextOptions: AIContextOptions(
                webEnabled: evaluationCase.webEnabled,
                memoryEnabled: AIMemorySettings.isEnabled
            ),
            retryPolicy: .none,
            metadata: [
                "evaluationCaseID": evaluationCase.id,
                "entryProvider": provider.rawValue,
                "promptTemplateID": promptConfiguration.templateID.rawValue,
                "promptScene": promptConfiguration.scene.rawValue,
                "promptModule": promptConfiguration.module,
                "outputFormat": promptConfiguration.outputFormat.rawValue
            ]
        )
    }

    private func evaluate(
        rules: [AIEvaluationRule],
        output: String,
        status: AIDebugStatus,
        durationMs: Int?,
        memoryHitCount: Int?
    ) -> [String] {
        var failures: [String] = []

        for rule in rules {
            switch rule {
            case .outputNotEmpty:
                if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    failures.append("输出为空")
                }

            case .outputContainsAny(let keywords):
                if keywords.isEmpty || !keywords.contains(where: output.contains) {
                    failures.append("输出未命中任一期望关键词：\(keywords.joined(separator: ", "))")
                }

            case .outputNotContainsAny(let keywords):
                if let matched = keywords.first(where: output.contains) {
                    failures.append("输出包含禁用关键词：\(matched)")
                }

            case .memoryHitAtLeast(let minimum):
                let actual = memoryHitCount ?? 0
                if actual < minimum {
                    failures.append("Memory 命中数不足：期望 >= \(minimum)，实际 \(actual)")
                }

            case .statusEquals(let expected):
                if status != expected {
                    failures.append("状态不匹配：期望 \(expected.rawValue)，实际 \(status.rawValue)")
                }

            case .durationLessThan(let threshold):
                guard let durationMs else {
                    failures.append("缺少耗时数据")
                    continue
                }
                if durationMs >= threshold {
                    failures.append("耗时超阈值：\(durationMs) ms >= \(threshold) ms")
                }
            }
        }

        return failures
    }
}
