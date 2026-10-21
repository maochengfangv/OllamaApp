import SwiftUI

struct ContentView: View {
    @StateObject private var ollamaManager = OllamaManager(provider: .ollama)
    @StateObject private var deepSeekManager = OllamaManager(provider: .deepseek)
    
    var body: some View {
        NavigationStack {
            // Sidebar for Chat History
            VStack(spacing: 3) {
                NavigationLink(destination: ChatView(provider: .ollama, manager: ollamaManager)
                    .onAppear {
                        ollamaManager.startNewChat()
                    }
                ) {
                    HStack {
                        Image(systemName: "square.and.pencil")
                        Text(LLMProvider.ollama.newChatTitle)
                        Spacer()
                    }
                    .font(.headline)
                    .foregroundColor(.primary)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(10)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .buttonStyle(PlainButtonStyle())

                NavigationLink(destination: ChatView(provider: .deepseek, manager: deepSeekManager)
                    .onAppear {
                        deepSeekManager.startNewChat()
                    }
                ) {
                    HStack {
                        Image(systemName: "square.and.pencil")
                        Text(LLMProvider.deepseek.newChatTitle)
                        Spacer()
                    }
                    .font(.headline)
                    .foregroundColor(.primary)
                    .padding()
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(10)
                }
                .padding(.horizontal)
                .buttonStyle(PlainButtonStyle())
                
                List {
                    Section(header: Text(LLMProvider.ollama.historyTitle)) {
                        ForEach(ollamaManager.chatHistory) { session in
                            NavigationLink(destination: ChatView(provider: .ollama, manager: ollamaManager)
                                .onAppear {
                                    ollamaManager.loadChat(session: session)
                                }
                            ) {
                                VStack(alignment: .leading) {
                                    Text(session.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Text(session.date, style: .date)
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            ollamaManager.deleteHistory(at: indexSet)
                        }
                    }

                    Section(header: Text(LLMProvider.deepseek.historyTitle)) {
                        ForEach(deepSeekManager.chatHistory) { session in
                            NavigationLink(destination: ChatView(provider: .deepseek, manager: deepSeekManager)
                                .onAppear {
                                    deepSeekManager.loadChat(session: session)
                                }
                            ) {
                                VStack(alignment: .leading) {
                                    Text(session.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Text(session.date, style: .date)
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            deepSeekManager.deleteHistory(at: indexSet)
                        }
                    }
                }
                .navigationTitle("Chats")
            }
        }
    }
}
    
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
