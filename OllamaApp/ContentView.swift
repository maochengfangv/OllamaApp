import SwiftUI

private enum HomeDestination: Hashable {
    case newChat(provider: LLMProvider)
    case historySession(provider: LLMProvider, sessionID: String)
}

struct ContentView: View {
    @StateObject private var ollamaManager = OllamaManager(provider: .ollama)
    @StateObject private var deepSeekManager = OllamaManager(provider: .deepseek)
    @State private var navigationPath: [HomeDestination] = []
    @State private var isHistoryDrawerPresented: Bool = false
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    homeContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .disabled(isHistoryDrawerPresented)
                        .blur(radius: isHistoryDrawerPresented ? 2 : 0)

                    if isHistoryDrawerPresented {
                        Color.black.opacity(0.18)
                            .ignoresSafeArea()
                            .onTapGesture {
                                closeHistoryDrawer()
                            }

                        historyDrawer(width: min(proxy.size.width * 0.84, 340))
                            .transition(.move(edge: .leading))
                    }
                }
            }
            .navigationTitle("AI Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: toggleHistoryDrawer) {
                        Image(systemName: "sidebar.left")
                    }
                    .accessibilityLabel("历史会话")
                }
            }
            .navigationDestination(for: HomeDestination.self) { destination in
                switch destination {
                case .newChat(let provider):
                    ChatView(provider: provider, manager: manager(for: provider))
                case .historySession(let provider, let sessionID):
                    HistorySessionPage(provider: provider, manager: manager(for: provider), sessionID: sessionID)
                }
            }
        }
    }

    private var homeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("开始新的 AI 会话")
                        .font(.title2.bold())
                    Text("左上角可以展开历史会话抽屉，继续之前的上下文；首页保留新建入口，让当前导航更聚焦。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)

                newChatCard(for: .ollama)
                newChatCard(for: .deepseek)

                VStack(alignment: .leading, spacing: 10) {
                    Label("交互说明", systemImage: "info.circle")
                        .font(.headline)
                    Text("1. 点击左上角按钮展开历史会话抽屉。")
                    Text("2. 点击列表中的会话，进入独立的历史会话页面。")
                    Text("3. 点击首页卡片，直接开始新的对话。")
                }
                .font(.subheadline)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func newChatCard(for provider: LLMProvider) -> some View {
        Button {
            openNewChat(for: provider)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "square.and.pencil")
                    .font(.title3)
                    .foregroundColor(accentColor(for: provider))
                    .frame(width: 36, height: 36)
                    .background(accentColor(for: provider).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.newChatTitle)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(provider == .ollama ? "本地模型，适合快速验证" : "云端模型，支持联网增强")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func historyDrawer(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("历史会话")
                        .font(.headline)
                    Text("从这里继续之前的上下文")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: closeHistoryDrawer) {
                    Image(systemName: "xmark")
                        .foregroundColor(.primary)
                        .padding(8)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            HistorySessionsView(
                ollamaManager: ollamaManager,
                deepSeekManager: deepSeekManager,
                onSelectSession: { provider, session in
                    openHistorySession(provider: provider, sessionID: session.id)
                }
            )
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 8)
        .padding(.leading, 12)
        .padding(.vertical, 8)
    }

    private func openNewChat(for provider: LLMProvider) {
        closeHistoryDrawer()
        manager(for: provider).startNewChat()
        navigationPath.append(.newChat(provider: provider))
    }

    private func openHistorySession(provider: LLMProvider, sessionID: String) {
        closeHistoryDrawer()
        navigationPath.append(.historySession(provider: provider, sessionID: sessionID))
    }

    private func manager(for provider: LLMProvider) -> OllamaManager {
        provider == .ollama ? ollamaManager : deepSeekManager
    }

    private func accentColor(for provider: LLMProvider) -> Color {
        provider == .ollama ? .blue : .green
    }

    private func toggleHistoryDrawer() {
        withAnimation(.easeInOut(duration: 0.22)) {
            isHistoryDrawerPresented.toggle()
        }
    }

    private func closeHistoryDrawer() {
        withAnimation(.easeInOut(duration: 0.22)) {
            isHistoryDrawerPresented = false
        }
    }
}
    
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
