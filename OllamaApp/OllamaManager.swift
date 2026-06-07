import Foundation
import Security

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

enum LLMProvider: String, Codable, CaseIterable, Identifiable {
    case ollama
    case deepseek

    var id: String { rawValue }
}

@MainActor
class OllamaManager: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating: Bool = false
    @Published var chatHistory: [ChatSession] = []
    
    let provider: LLMProvider

    var currentSessionId: String?
    private let historyKey: String
    
    private var currentTask: Task<Void, Never>?
    
    // Use 127.0.0.1 instead of localhost because Ollama listens on IPv4 by default, 
    // and iOS simulator might resolve localhost to IPv6 (::1), causing connection refused.
    private let baseURL = "http://127.0.0.1:11434/api/generate"
    private let deepSeekBaseURLKey = "DeepSeekBaseURL"
    
    init(provider: LLMProvider) {
        self.provider = provider
        self.historyKey = "ChatHistory_" + provider.rawValue
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
        var data = UserDefaults.standard.data(forKey: historyKey)
        if data == nil, provider == .ollama {
            data = UserDefaults.standard.data(forKey: "OllamaChatHistory")
            if let data {
                UserDefaults.standard.set(data, forKey: historyKey)
            }
        }

        guard let data else { return }
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

    func resend(messageId: UUID, model: String, webEnabled: Bool = false) async {
        guard !isGenerating else { return }
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        guard messages[index].role == .user else { return }

        let trimmedPrompt = messages[index].content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return }

        isGenerating = true
        messages = Array(messages.prefix(index + 1))
        messages.append(ChatMessage(role: .model, content: ""))

        currentTask = Task {
            do {
                switch self.provider {
                case .ollama:
                    try await self.generateWithOllama(prompt: trimmedPrompt, model: model)
                case .deepseek:
                    try await self.generateWithDeepSeek(model: model, webEnabled: webEnabled, query: trimmedPrompt)
                }
            } catch {
                if let lastIndex = self.messages.indices.last {
                    if Task.isCancelled {
                        self.messages[lastIndex].content += "\n[Stopped]"
                    } else {
                        print("Error: \(error)")
                        self.messages[lastIndex].content = "Error: \(error.localizedDescription)"
                    }
                }
                self.isGenerating = false
                self.updateCurrentSession()
            }
        }
        await currentTask?.value
    }
    
    func generate(prompt: String, model: String, webEnabled: Bool = false) async {
        self.isGenerating = true
        self.messages.append(ChatMessage(role: .user, content: prompt))
        self.messages.append(ChatMessage(role: .model, content: ""))
        
        currentTask = Task {
            do {
                switch self.provider {
                case .ollama:
                    try await self.generateWithOllama(prompt: prompt, model: model)
                case .deepseek:
                    try await self.generateWithDeepSeek(model: model, webEnabled: webEnabled, query: prompt)
                }
            } catch {
                if let lastIndex = self.messages.indices.last {
                    if Task.isCancelled {
                        self.messages[lastIndex].content += "\n[Stopped]"
                    } else {
                        print("Error: \(error)")
                        self.messages[lastIndex].content = "Error: \(error.localizedDescription)"
                    }
                }
                self.isGenerating = false
                self.updateCurrentSession()
            }
        }
        await currentTask?.value
    }

    private func generateWithOllama(prompt: String, model: String) async throws {
        guard let url = URL(string: baseURL) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let ollamaRequest = OllamaRequest(model: model, prompt: prompt, stream: true)
        request.httpBody = try JSONEncoder().encode(ollamaRequest)

        let (result, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            var errorBody = ""
            for try await line in result.lines {
                errorBody += line + "\n"
            }

            if let lastIndex = self.messages.indices.last {
                self.messages[lastIndex].content = "Server error: \(statusCode)\nDetails: \(errorBody)"
            }
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
    }

    private struct DeepSeekChatCompletionRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        struct Thinking: Encodable {
            let type: String
        }

        let model: String
        let messages: [Message]
        let thinking: Thinking?
        let reasoning_effort: String?
        let stream: Bool
    }

    private struct DeepSeekStreamResponse: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }

            let delta: Delta
        }

        let choices: [Choice]
    }

    private struct DeepSeekChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }

            let message: Message
        }

        let choices: [Choice]
    }

    private func generateWithDeepSeek(model: String, webEnabled: Bool, query: String) async throws {
        let apiKey = KeychainStore.shared.get(service: Bundle.main.bundleIdentifier ?? "OllamaApp", account: "deepseek_api_key")
        guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if let lastIndex = self.messages.indices.last {
                self.messages[lastIndex].content = "DeepSeek API Key 未配置。请在 DeepSeek 设置里填写后再试。"
            }
            self.isGenerating = false
            self.updateCurrentSession()
            return
        }

        let base = (UserDefaults.standard.string(forKey: deepSeekBaseURLKey) ?? "https://api.deepseek.com")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let urls = deepSeekChatCompletionsURLs(fromBase: base)
        guard urls.first != nil else {
            if let lastIndex = self.messages.indices.last {
                self.messages[lastIndex].content = "DeepSeek Base URL 不合法：\(base)"
            }
            self.isGenerating = false
            self.updateCurrentSession()
            return
        }

        var history: [DeepSeekChatCompletionRequest.Message] = [
            .init(role: "system", content: "You are a helpful assistant.")
        ]

        if webEnabled {
            var webContext: String?

            if let weatherContext = try? await fetchWeatherContext(query: query), !weatherContext.isEmpty {
                webContext = weatherContext
                history.append(.init(
                    role: "system",
                    content: "You have access to the following real-time data. Use it to answer the user. Do not say you cannot access real-time information.\n\n\(weatherContext)"
                ))
            } else if let context = try? await fetchDuckDuckGoContext(query: query), !context.isEmpty {
                webContext = context
                history.append(.init(
                    role: "system",
                    content: "Web search results for: \(query)\n\(context)\nUse the above information when it is relevant and cite URLs. Do not say you cannot browse."
                ))
            } else {
                webContext = "联网失败：未获取到可用结果（可能被网络限制或查询源无返回）"
            }

            if let webContext, let lastIndex = self.messages.indices.last {
                let existing = self.messages[lastIndex].content.trimmingCharacters(in: .whitespacesAndNewlines)
                if existing.isEmpty {
                    self.messages[lastIndex].content = "【联网结果】\n" + String(webContext.prefix(1500))
                } else {
                    self.messages[lastIndex].content = "【联网结果】\n" + String(webContext.prefix(1500)) + "\n\n" + existing
                }
            }
        }

        history += self.messages.dropLast().compactMap { message in
            switch message.role {
            case .user:
                return .init(role: "user", content: message.content)
            case .model:
                guard !message.content.isEmpty else { return nil }
                return .init(role: "assistant", content: message.content)
            }
        }

        let body = DeepSeekChatCompletionRequest(
            model: model,
            messages: history,
            thinking: .init(type: "enabled"),
            reasoning_effort: "high",
            stream: false
        )

        let encodedBody = try JSONEncoder().encode(body)

        var lastErrorMessage: String?

        for (index, url) in urls.enumerated() {
            if Task.isCancelled { break }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = encodedBody

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                lastErrorMessage = "DeepSeek 响应异常"
                continue
            }

            if httpResponse.statusCode == 200 {
                if let decoded = try? JSONDecoder().decode(DeepSeekChatCompletionResponse.self, from: data),
                   let content = decoded.choices.first?.message.content,
                   let lastIndex = self.messages.indices.last {
                    let existingPrefix = self.messages[lastIndex].content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if existingPrefix.hasPrefix("【联网结果】") {
                        self.messages[lastIndex].content = existingPrefix + "\n\n【回答】\n" + content
                    } else {
                        self.messages[lastIndex].content = content
                    }
                } else if let lastIndex = self.messages.indices.last {
                    self.messages[lastIndex].content = "DeepSeek 响应解析失败"
                }

                self.isGenerating = false
                self.updateCurrentSession()
                return
            }

            let errorBody = String(data: data, encoding: .utf8) ?? ""
            lastErrorMessage = "DeepSeek 请求失败：\(httpResponse.statusCode)\n\(errorBody)"

            if httpResponse.statusCode == 404, index < urls.count - 1 {
                continue
            }

            break
        }

        if let lastIndex = self.messages.indices.last {
            self.messages[lastIndex].content = lastErrorMessage ?? "DeepSeek 请求失败"
        }
        self.isGenerating = false
        self.updateCurrentSession()
    }

    private func deepSeekChatCompletionsURLs(fromBase base: String) -> [URL] {
        var normalized = base
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }

        var bases: [String] = [normalized]
        if normalized.hasSuffix("/v1") {
            bases.append(String(normalized.dropLast(3)))
        } else {
            bases.append(normalized + "/v1")
        }

        var urls: [URL] = []
        for candidateBase in bases {
            if let url = URL(string: candidateBase + "/chat/completions") {
                urls.append(url)
            }
            if let url = URL(string: candidateBase + "/v1/chat/completions") {
                urls.append(url)
            }
        }

        var seen = Set<String>()
        return urls.filter { url in
            let key = url.absoluteString
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private struct DuckDuckGoInstantAnswer: Decodable {
        struct RelatedTopic: Decodable {
            let Text: String?
            let FirstURL: String?
            let Topics: [RelatedTopic]?
        }

        let AbstractText: String?
        let AbstractURL: String?
        let RelatedTopics: [RelatedTopic]?
    }

    private func fetchDuckDuckGoContext(query: String) async throws -> String? {
        var components = URLComponents(string: "https://api.duckduckgo.com/")!
        components.queryItems = [
            .init(name: "q", value: query),
            .init(name: "format", value: "json"),
            .init(name: "no_html", value: "1"),
            .init(name: "skip_disambig", value: "1")
        ]

        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }

        let decoded = try JSONDecoder().decode(DuckDuckGoInstantAnswer.self, from: data)

        var lines: [String] = []
        if let abstract = decoded.AbstractText, !abstract.isEmpty {
            if let url = decoded.AbstractURL, !url.isEmpty {
                lines.append("Abstract: \(abstract) (\(url))")
            } else {
                lines.append("Abstract: \(abstract)")
            }
        }

        func flatten(_ items: [DuckDuckGoInstantAnswer.RelatedTopic]?) -> [DuckDuckGoInstantAnswer.RelatedTopic] {
            guard let items else { return [] }
            var out: [DuckDuckGoInstantAnswer.RelatedTopic] = []
            for item in items {
                if let topics = item.Topics, !topics.isEmpty {
                    out.append(contentsOf: flatten(topics))
                } else {
                    out.append(item)
                }
            }
            return out
        }

        let topics = flatten(decoded.RelatedTopics).compactMap { topic -> String? in
            guard let text = topic.Text, !text.isEmpty else { return nil }
            if let url = topic.FirstURL, !url.isEmpty {
                return "\(text) (\(url))"
            }
            return text
        }

        for (i, item) in topics.prefix(5).enumerated() {
            lines.append("\(i + 1). \(item)")
        }

        let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { return nil }
        return String(joined.prefix(1500))
    }

    private struct OpenMeteoGeocodingResponse: Decodable {
        struct Result: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let country: String?
            let admin1: String?
        }

        let results: [Result]?
    }

    private struct OpenMeteoForecastResponse: Decodable {
        struct Current: Decodable {
            let time: String
            let temperature_2m: Double?
            let apparent_temperature: Double?
            let relative_humidity_2m: Double?
            let wind_speed_10m: Double?
            let weather_code: Int?
        }

        let current: Current?
    }

    private func fetchWeatherContext(query: String) async throws -> String? {
        guard let locationName = extractLocationForWeather(query: query) else { return nil }

        var geocode = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        geocode.queryItems = [
            .init(name: "name", value: locationName),
            .init(name: "count", value: "1"),
            .init(name: "language", value: "zh"),
            .init(name: "format", value: "json")
        ]

        guard let geocodeURL = geocode.url else { return nil }
        let (geocodeData, geocodeResponse) = try await URLSession.shared.data(from: geocodeURL)
        guard let geocodeHTTP = geocodeResponse as? HTTPURLResponse, geocodeHTTP.statusCode == 200 else { return nil }

        let geocodeDecoded = try JSONDecoder().decode(OpenMeteoGeocodingResponse.self, from: geocodeData)
        guard let place = geocodeDecoded.results?.first else { return nil }

        var forecast = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        forecast.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code"),
            .init(name: "timezone", value: "auto")
        ]

        guard let forecastURL = forecast.url else { return nil }
        let (forecastData, forecastResponse) = try await URLSession.shared.data(from: forecastURL)
        guard let forecastHTTP = forecastResponse as? HTTPURLResponse, forecastHTTP.statusCode == 200 else { return nil }

        let forecastDecoded = try JSONDecoder().decode(OpenMeteoForecastResponse.self, from: forecastData)
        guard let current = forecastDecoded.current else { return nil }

        let displayPlace: String = {
            var parts: [String] = [place.name]
            if let admin1 = place.admin1, !admin1.isEmpty, admin1 != place.name { parts.append(admin1) }
            if let country = place.country, !country.isEmpty { parts.append(country) }
            return parts.joined(separator: ", ")
        }()

        var lines: [String] = []
        lines.append("Realtime weather (联网模式) for: \(displayPlace)")
        lines.append("Time: \(current.time)")

        if let t = current.temperature_2m { lines.append("Temperature: \(String(format: "%.1f", t))°C") }
        if let at = current.apparent_temperature { lines.append("Feels like: \(String(format: "%.1f", at))°C") }
        if let h = current.relative_humidity_2m { lines.append("Humidity: \(Int(h))%") }
        if let w = current.wind_speed_10m { lines.append("Wind: \(String(format: "%.1f", w)) km/h") }
        if let code = current.weather_code { lines.append("Condition: \(openMeteoWeatherDescription(code: code)) (code \(code))") }

        lines.append("Source: https://open-meteo.com/ (geocoding-api.open-meteo.com, api.open-meteo.com)")
        return lines.joined(separator: "\n")
    }

    private func extractLocationForWeather(query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        let triggers: [String] = ["天气", "气温", "温度", "体感", "湿度", "风速", "weather", "temperature"]
        guard triggers.contains(where: { lower.contains($0.lowercased()) }) else { return nil }

        let markers: [String] = ["天气", "气温", "温度", "weather", "temperature"]
        var markerRange: Range<String.Index>?
        for marker in markers {
            if let range = trimmed.range(of: marker, options: [.backwards, .caseInsensitive]) {
                markerRange = range
                break
            }
        }

        if let markerRange {
            let before = trimmed[..<markerRange.lowerBound]
            var candidate = String(before).trimmingCharacters(in: .whitespacesAndNewlines)
            candidate = candidate.replacingOccurrences(of: "的", with: "")
            candidate = candidate.replacingOccurrences(of: "今天", with: "")
            candidate = candidate.replacingOccurrences(of: "今日", with: "")
            candidate = candidate.replacingOccurrences(of: "现在", with: "")
            candidate = candidate.replacingOccurrences(of: "实时", with: "")
            candidate = candidate.replacingOccurrences(of: "一下", with: "")
            candidate = candidate.replacingOccurrences(of: "查询", with: "")
            candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: " ，,。.!！？?、:：；;\"'“”‘’()（）[]【】"))

            if candidate.count > 8 {
                candidate = String(candidate.suffix(8))
            }

            candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.isEmpty { return nil }
            return candidate
        }

        return nil
    }

    private func openMeteoWeatherDescription(code: Int) -> String {
        switch code {
        case 0: return "晴朗"
        case 1, 2, 3: return "多云"
        case 45, 48: return "有雾"
        case 51, 53, 55, 56, 57: return "毛毛雨"
        case 61, 63, 65, 66, 67: return "下雨"
        case 71, 73, 75, 77: return "下雪"
        case 80, 81, 82: return "阵雨"
        case 95: return "雷暴"
        case 96, 99: return "雷暴伴冰雹"
        default: return "未知"
        }
    }
}

final class KeychainStore {
    static let shared = KeychainStore()

    func set(_ value: String, service: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data

        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
    }

    func get(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
