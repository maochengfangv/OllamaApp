import SwiftUI

struct HistorySessionPage: View {
    let provider: LLMProvider
    @ObservedObject var manager: OllamaManager
    let sessionID: String

    var body: some View {
        ChatView(provider: provider, manager: manager)
            .onAppear {
                manager.loadChat(sessionID: sessionID)
            }
    }
}
