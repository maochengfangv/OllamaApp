import Foundation
import OSLog

enum ChatTelemetryEvent: Equatable {
    case generationStarted(
        requestID: UUID,
        provider: LLMProvider,
        model: String,
        webEnabled: Bool,
        historyCount: Int,
        timeoutMs: Int,
        retryLimit: Int,
        fallbackProvider: LLMProvider?
    )
    case generationCompleted(
        requestID: UUID,
        provider: LLMProvider,
        model: String,
        durationMs: Int,
        firstTokenLatencyMs: Int?,
        retryCount: Int,
        fallbackUsed: Bool,
        outputLength: Int,
        estimatedCost: Double?
    )
    case generationCancelled(
        requestID: UUID,
        provider: LLMProvider,
        model: String,
        durationMs: Int,
        retryCount: Int,
        fallbackUsed: Bool,
        outputLength: Int
    )
    case generationFailed(
        requestID: UUID,
        provider: LLMProvider,
        model: String,
        durationMs: Int,
        retryCount: Int,
        fallbackUsed: Bool,
        errorCode: AIClientErrorCode,
        message: String
    )
    case sessionLoaded(provider: LLMProvider, sessionId: String, messageCount: Int)
    case sessionDeleted(provider: LLMProvider, sessionId: String)
    case legacyHistoryMigrated(provider: LLMProvider, sessionCount: Int)

    var name: String {
        switch self {
        case .generationStarted: return "generation_started"
        case .generationCompleted: return "generation_completed"
        case .generationCancelled: return "generation_cancelled"
        case .generationFailed: return "generation_failed"
        case .sessionLoaded: return "session_loaded"
        case .sessionDeleted: return "session_deleted"
        case .legacyHistoryMigrated: return "legacy_history_migrated"
        }
    }

    var message: String {
        switch self {
        case .generationStarted(let requestID, let provider, let model, let webEnabled, let historyCount, let timeoutMs, let retryLimit, let fallbackProvider):
            return "requestID=\(requestID.uuidString) provider=\(provider.rawValue) model=\(model) webEnabled=\(webEnabled) historyCount=\(historyCount) timeoutMs=\(timeoutMs) retryLimit=\(retryLimit) fallbackProvider=\(fallbackProvider?.rawValue ?? "none")"
        case .generationCompleted(let requestID, let provider, let model, let durationMs, let firstTokenLatencyMs, let retryCount, let fallbackUsed, let outputLength, let estimatedCost):
            return "requestID=\(requestID.uuidString) provider=\(provider.rawValue) model=\(model) durationMs=\(durationMs) firstTokenLatencyMs=\(stringValue(firstTokenLatencyMs)) retryCount=\(retryCount) fallbackUsed=\(fallbackUsed) outputLength=\(outputLength) estimatedCost=\(stringValue(estimatedCost))"
        case .generationCancelled(let requestID, let provider, let model, let durationMs, let retryCount, let fallbackUsed, let outputLength):
            return "requestID=\(requestID.uuidString) provider=\(provider.rawValue) model=\(model) durationMs=\(durationMs) retryCount=\(retryCount) fallbackUsed=\(fallbackUsed) outputLength=\(outputLength)"
        case .generationFailed(let requestID, let provider, let model, let durationMs, let retryCount, let fallbackUsed, let errorCode, let message):
            return "requestID=\(requestID.uuidString) provider=\(provider.rawValue) model=\(model) durationMs=\(durationMs) retryCount=\(retryCount) fallbackUsed=\(fallbackUsed) errorCode=\(errorCode.rawValue) error=\(message)"
        case .sessionLoaded(let provider, let sessionId, let messageCount):
            return "provider=\(provider.rawValue) sessionId=\(sessionId) messageCount=\(messageCount)"
        case .sessionDeleted(let provider, let sessionId):
            return "provider=\(provider.rawValue) sessionId=\(sessionId)"
        case .legacyHistoryMigrated(let provider, let sessionCount):
            return "provider=\(provider.rawValue) sessionCount=\(sessionCount)"
        }
    }
}

protocol ChatTelemetryRecording {
    func record(_ event: ChatTelemetryEvent)
}

final class ChatTelemetryRecorder: ChatTelemetryRecording {
    static let shared = ChatTelemetryRecorder()

    private let logger: Logger

    init(subsystem: String = Bundle.main.bundleIdentifier ?? "OllamaApp", category: String = "LLM") {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    func record(_ event: ChatTelemetryEvent) {
        logger.info("\(event.name, privacy: .public) \(event.message, privacy: .public)")
    }
}

private func stringValue<T>(_ value: T?) -> String {
    guard let value else { return "nil" }
    return String(describing: value)
}
