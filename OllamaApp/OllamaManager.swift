import Foundation

struct OllamaRequest: Codable {
    let model: String
    let prompt: String
    let stream: Bool
}

struct OllamaResponse: Codable {
    let model: String
    let created_at: String
    let response: String
    let done: Bool
}

struct ChatMessage: Identifiable, Equatable, Codable {
    var id = UUID()
    let role: MessageRole
    var content: String
    
    enum MessageRole: String, Codable {
        case user, model
    }
}

struct ChatSession: Identifiable, Codable, Equatable {
    var id: String
    var messages: [ChatMessage]
    var title: String
    var date: Date
}

@MainActor
class OllamaManager: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating: Bool = false
    @Published var chatHistory: [ChatSession] = []
    
    var currentSessionId: String?
    private let historyKey = "OllamaChatHistory"
    
    private var currentTask: Task<Void, Never>?
    
    // Use 127.0.0.1 instead of localhost because Ollama listens on IPv4 by default, 
    // and iOS simulator might resolve localhost to IPv6 (::1), causing connection refused.
    private let baseURL = "http://127.0.0.1:11434/api/generate"
    
    init() {
        loadHistory()
    }
    
    func startNewChat() {
        messages = []
        currentSessionId = nil
    }
    
    func loadChat(session: ChatSession) {
        messages = session.messages
        currentSessionId = session.id
    }
    
    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(chatHistory)
            UserDefaults.standard.set(data, forKey: historyKey)
        } catch {
            print("Failed to save history: \(error)")
        }
    }
    
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey) else { return }
        do {
            chatHistory = try JSONDecoder().decode([ChatSession].self, from: data)
        } catch {
            print("Failed to load history: \(error)")
        }
    }
    
    func deleteHistory(at offsets: IndexSet) {
        chatHistory.remove(atOffsets: offsets)
        saveHistory()
        
        // If the current session was deleted, start a new chat
        if let currentId = currentSessionId, !chatHistory.contains(where: { $0.id == currentId }) {
            startNewChat()
        }
    }
    
    private func updateCurrentSession() {
        guard !messages.isEmpty else { return }
        
        let title = messages.last(where: { $0.role == .user })?.content ?? "New Chat"
        let shortTitle = String(title.prefix(15)) + (title.count > 15 ? "..." : "")
        
        if let sessionId = currentSessionId {
            if let index = chatHistory.firstIndex(where: { $0.id == sessionId }) {
                chatHistory[index].messages = messages
                chatHistory[index].title = shortTitle
            }
        } else {
            let newSessionId = UUID().uuidString
            currentSessionId = newSessionId
            let newSession = ChatSession(id: newSessionId, messages: messages, title: shortTitle, date: Date())
            chatHistory.insert(newSession, at: 0) // Stack-like, newest at the top
        }
        
        saveHistory()
    }
    
    func stopGenerating() {
        currentTask?.cancel()
        currentTask = nil
        isGenerating = false
        updateCurrentSession()
    }
    
    func generate(prompt: String, model: String = "phi3") async {
        guard let url = URL(string: baseURL) else { return }
        
        self.isGenerating = true
        self.messages.append(ChatMessage(role: .user, content: prompt))
        self.messages.append(ChatMessage(role: .model, content: ""))
        
        currentTask = Task {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let ollamaRequest = OllamaRequest(model: model, prompt: prompt, stream: true)
            
            do {
                request.httpBody = try JSONEncoder().encode(ollamaRequest)
                
                let (result, response) = try await URLSession.shared.bytes(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    
                    // Read the error body if available
                    var errorBody = ""
                    for try await line in result.lines {
                        errorBody += line + "\n"
                    }
                    
                    if let lastIndex = self.messages.indices.last {
                        self.messages[lastIndex].content = "Server error: \(statusCode)\nDetails: \(errorBody)"
                    }
                    print("Server returned status code: \(statusCode)")
                    print("Response body: \(errorBody)")
                    
                    self.isGenerating = false
                    return
                }
                
                for try await line in result.lines {
                    if Task.isCancelled { break }
                    if let data = line.data(using: .utf8),
                       let ollamaResponse = try? JSONDecoder().decode(OllamaResponse.self, from: data) {
                        if let lastIndex = self.messages.indices.last {
                            self.messages[lastIndex].content += ollamaResponse.response
                        }
                    }
                }
                
                self.isGenerating = false
                self.updateCurrentSession()
                
            } catch {
                if let lastIndex = self.messages.indices.last {
                    if Task.isCancelled {
                        self.messages[lastIndex].content += "\n[Stopped]"
                    } else {
                        print("Error: \(error)")
                        self.messages[lastIndex].content = "Error: \(error.localizedDescription)\nEnsure Ollama is running and accessible."
                    }
                }
                self.isGenerating = false
                self.updateCurrentSession()
            }
        }
        await currentTask?.value
    }
}
