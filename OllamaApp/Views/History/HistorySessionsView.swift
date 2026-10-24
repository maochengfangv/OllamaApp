import SwiftUI

struct HistorySessionsView: View {
    @ObservedObject var deepSeekManager: OllamaManager
    let onSelectSession: (LLMProvider, ChatSession) -> Void

    var body: some View {
        List {
            providerSection(provider: .deepseek, manager: deepSeekManager)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    @ViewBuilder
    private func providerSection(provider: LLMProvider, manager: OllamaManager) -> some View {
        Section(provider.historyTitle) {
            if manager.chatHistory.isEmpty {
                Text("暂无历史会话")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(manager.chatHistory) { session in
                    Button {
                        onSelectSession(provider, session)
                    } label: {
                        HistorySessionRow(provider: provider, session: session)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    manager.deleteHistory(at: indexSet)
                }
            }
        }
    }
}

private struct HistorySessionRow: View {
    let provider: LLMProvider
    let session: ChatSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .foregroundColor(.green)
                .frame(width: 28, height: 28)
                .background(Color.green.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(provider.displayName)
                    Text(session.date, style: .date)
                    Text(session.date, style: .time)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
