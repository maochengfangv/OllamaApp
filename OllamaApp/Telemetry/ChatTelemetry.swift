import Foundation
import OSLog

enum ChatTelemetryEvent: Equatable {
    case generationStarted(provider: LLMProvider, model: String, webEnabled: Bool, historyCount: Int)
    case generationCompleted(provider: LLMProvider, model: String, durationMs: Int, outputLength: Int)
    case generationCancelled(provider: LLMProvider, model: String, durationMs: Int, outputLength: Int)
    case generationFailed(provider: LLMProvider, model: String, durationMs: Int, message: String)
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
        case .generationStarted(let provider, let model, let webEnabled, let historyCount):
            return "provider=\(provider.rawValue) model=\(model) webEnabled=\(webEnabled) historyCount=\(historyCount)"
        case .generationCompleted(let provider, let model, let durationMs, let outputLength):
            return "provider=\(provider.rawValue) model=\(model) durationMs=\(durationMs) outputLength=\(outputLength)"
        case .generationCancelled(let provider, let model, let durationMs, let outputLength):
            return "provider=\(provider.rawValue) model=\(model) durationMs=\(durationMs) outputLength=\(outputLength)"
        case .generationFailed(let provider, let model, let durationMs, let message):
            return "provider=\(provider.rawValue) model=\(model) durationMs=\(durationMs) error=\(message)"
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
