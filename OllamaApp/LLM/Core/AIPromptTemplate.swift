import Foundation

enum AIPromptTemplateID: String, Codable, Equatable, CaseIterable {
    case generalChat
    case engineeringChat
    case webResearch
    case requirementSummary
    case testCaseGeneration
    case conciseAssistant
}

enum AIPromptScene: String, Codable, Equatable {
    case chat
    case research
    case requirement
    case testing

    var displayName: String {
        rawValue
    }
}

enum AIPromptOutputFormat: String, Codable, Equatable {
    case paragraph
    case markdownSections
    case markdownBullets
    case markdownChecklist

    var displayName: String {
        switch self {
        case .paragraph:
            return "paragraph"
        case .markdownSections:
            return "markdown sections"
        case .markdownBullets:
            return "markdown bullet list"
        case .markdownChecklist:
            return "markdown checklist"
        }
    }
}

struct AIPromptTemplateConfiguration: Equatable {
    let templateID: AIPromptTemplateID
    let scene: AIPromptScene
    let module: String
    let outputFormat: AIPromptOutputFormat
    let variables: [String: String]
}

struct AIPromptOverrides: Equatable {
    let templateID: AIPromptTemplateID?
    let scene: AIPromptScene?
    let module: String?
    let outputFormat: AIPromptOutputFormat?
    let variables: [String: String]

    init(
        templateID: AIPromptTemplateID? = nil,
        scene: AIPromptScene? = nil,
        module: String? = nil,
        outputFormat: AIPromptOutputFormat? = nil,
        variables: [String: String] = [:]
    ) {
        self.templateID = templateID
        self.scene = scene
        self.module = module
        self.outputFormat = outputFormat
        self.variables = variables
    }

    static let none = AIPromptOverrides()
}

enum AIPromptTemplateLibrary {
    static func render(id: AIPromptTemplateID, variables: [String: String] = [:]) -> String {
        let template = templateString(for: id)
        let resolvedVariables = defaultVariables.merging(variables) { _, new in new }
        return resolvedVariables.reduce(template) { partialResult, item in
            partialResult.replacingOccurrences(of: "{{\(item.key)}}", with: item.value)
        }
    }

    private static func templateString(for id: AIPromptTemplateID) -> String {
        switch id {
        case .generalChat:
            return "You are a helpful assistant for the {{scene}} scene. Focus on the {{module}} module. Respond using {{output_format}}."
        case .engineeringChat:
            return "You are a pragmatic senior software engineer working in the {{scene}} scene. Focus on the {{module}} module. Give accurate, implementation-oriented answers, call out tradeoffs, keep responses grounded in production constraints, and format the answer as {{output_format}}."
        case .webResearch:
            return "You are a research-oriented assistant for the {{scene}} scene. Focus on the {{module}} module. Synthesize online context carefully, distinguish facts from guesses, include sources when web context is present, and respond using {{output_format}}."
        case .requirementSummary:
            return "You are a product and engineering assistant for the {{scene}} scene. Focus on the {{module}} module. Summarize requirements clearly, identify modules, APIs, edge cases, and delivery risks, and organize the answer using {{output_format}}."
        case .testCaseGeneration:
            return "You are a QA-minded engineering assistant for the {{scene}} scene. Focus on the {{module}} module. Generate structured test points, cover normal flow, edge cases, error handling, and regression risk, and return the answer using {{output_format}}."
        case .conciseAssistant:
            return "You are a concise assistant for the {{scene}} scene. Focus on the {{module}} module. Respond directly, keep answers brief, and use {{output_format}}."
        }
    }

    private static let defaultVariables: [String: String] = [
        "scene": AIPromptScene.chat.displayName,
        "module": "general",
        "output_format": AIPromptOutputFormat.paragraph.displayName
    ]
}

enum AIPromptTemplateSelector {
    static func selectConfiguration(for prompt: String, webEnabled: Bool) -> AIPromptTemplateConfiguration {
        let normalized = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let module = inferModule(from: normalized)
        if webEnabled {
            return makeConfiguration(
                templateID: .webResearch,
                scene: .research,
                module: module,
                outputFormat: .markdownBullets
            )
        }

        let requirementKeywords = ["需求", "prd", "product requirement", "接口草案", "模块设计", "方案设计"]
        if requirementKeywords.contains(where: normalized.contains) {
            return makeConfiguration(
                templateID: .requirementSummary,
                scene: .requirement,
                module: module,
                outputFormat: .markdownSections
            )
        }

        let testKeywords = ["测试点", "test case", "测试用例", "回归", "边界条件", "qa"]
        if testKeywords.contains(where: normalized.contains) {
            return makeConfiguration(
                templateID: .testCaseGeneration,
                scene: .testing,
                module: module,
                outputFormat: .markdownChecklist
            )
        }

        return makeConfiguration(
            templateID: .engineeringChat,
            scene: .chat,
            module: module,
            outputFormat: .markdownSections
        )
    }

    static func resolveConfiguration(
        for prompt: String,
        webEnabled: Bool,
        overrides: AIPromptOverrides = .none
    ) -> AIPromptTemplateConfiguration {
        let inferred = selectConfiguration(for: prompt, webEnabled: webEnabled)
        let scene = overrides.scene ?? inferred.scene
        let module = normalizedModule(overrides.module) ?? inferred.module
        let outputFormat = overrides.outputFormat ?? inferred.outputFormat
        let templateID = overrides.templateID ?? inferred.templateID
        let variables = inferred.variables
            .merging(overrides.variables) { _, new in new }
            .merging(
                [
                    "scene": scene.displayName,
                    "module": module,
                    "output_format": outputFormat.displayName
                ]
            ) { _, new in new }

        return AIPromptTemplateConfiguration(
            templateID: templateID,
            scene: scene,
            module: module,
            outputFormat: outputFormat,
            variables: variables
        )
    }

    private static func makeConfiguration(
        templateID: AIPromptTemplateID,
        scene: AIPromptScene,
        module: String,
        outputFormat: AIPromptOutputFormat
    ) -> AIPromptTemplateConfiguration {
        AIPromptTemplateConfiguration(
            templateID: templateID,
            scene: scene,
            module: module,
            outputFormat: outputFormat,
            variables: [
                "scene": scene.displayName,
                "module": module,
                "output_format": outputFormat.displayName
            ]
        )
    }

    private static func inferModule(from normalizedPrompt: String) -> String {
        let modules: [(String, [String])] = [
            ("ui", ["ui", "view", "页面", "界面", "交互", "swiftui"]),
            ("networking", ["network", "api", "请求", "接口", "联网", "urlsession"]),
            ("provider", ["provider", "模型", "ollama", "deepseek"]),
            ("persistence", ["store", "cache", "持久化", "session", "存储"]),
            ("telemetry", ["telemetry", "埋点", "监控", "日志", "cost", "token"]),
            ("testing", ["测试", "test case", "测试用例", "qa", "回归"])
        ]

        for (module, keywords) in modules {
            if keywords.contains(where: normalizedPrompt.contains) {
                return module
            }
        }

        return "general"
    }

    private static func normalizedModule(_ module: String?) -> String? {
        guard let module else {
            return nil
        }
        let trimmed = module.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed.lowercased()
    }
}
