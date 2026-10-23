import Foundation

struct LLMContextEnvelope {
    let systemMessages: [String]
    let previewText: String?

    static let empty = LLMContextEnvelope(systemMessages: [], previewText: nil)
}

protocol LLMContextBuilding {
    func buildContext(for request: AIRequest) async throws -> LLMContextEnvelope
}
