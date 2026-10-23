import Foundation

enum AIDebugStatus: String, Equatable {
    case idle
    case generating
    case completed
    case cancelled
    case failed
}

struct AIDebugSnapshot: Equatable {
    var requestID: UUID
    var sessionID: String?
    var status: AIDebugStatus
    var promptPreview: String
    var entryProvider: LLMProvider
    var resolvedProvider: LLMProvider?
    var fallbackProvider: LLMProvider?
    var routePolicySummary: String
    var model: String
    var promptTemplateID: AIPromptTemplateID
    var webEnabled: Bool
    var retryLimit: Int
    var retryCount: Int
    var fallbackUsed: Bool
    var durationMs: Int?
    var firstTokenLatencyMs: Int?
    var usage: AIUsage?
    var errorCode: AIClientErrorCode?
    var errorMessage: String?
    var updatedAt: Date
}
