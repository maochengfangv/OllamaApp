import Foundation

struct ChatSessionIndexItem: Codable, Equatable {
    let id: String
    let title: String
    let date: Date
}

final class ChatSessionStore {
    private let provider: LLMProvider
    private let fileManager = FileManager.default
    private let legacyKeys: [String]
    private let userDefaults: UserDefaults
    private let rootDirectoryOverride: URL?
    private let telemetry: any ChatTelemetryRecording

    init(
        provider: LLMProvider,
        legacyKeys: [String],
        userDefaults: UserDefaults = .standard,
        rootDirectoryOverride: URL? = nil,
        telemetry: any ChatTelemetryRecording = ChatTelemetryRecorder.shared
    ) {
        self.provider = provider
        self.legacyKeys = legacyKeys
        self.userDefaults = userDefaults
        self.rootDirectoryOverride = rootDirectoryOverride
        self.telemetry = telemetry
    }

    func loadSessionSummaries() -> [ChatSession] {
        migrateLegacyHistoryIfNeeded()

        let items = loadIndexItems()
        return items.map {
            ChatSession(id: $0.id, messages: [], title: $0.title, date: $0.date)
        }
    }

    func loadSession(id: String) -> ChatSession? {
        let url = sessionFileURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ChatSession.self, from: data)
    }

    func saveSession(_ session: ChatSession) {
        ensureBaseDirectory()
        let url = sessionFileURL(for: session.id)
        do {
            let data = try JSONEncoder().encode(session)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save session \(session.id): \(error)")
        }
    }

    func deleteSession(id: String) {
        let url = sessionFileURL(for: id)
        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                print("Failed to delete session \(id): \(error)")
            }
        }
    }

    func saveIndex(from summaries: [ChatSession]) {
        ensureBaseDirectory()
        let items = summaries.map { ChatSessionIndexItem(id: $0.id, title: $0.title, date: $0.date) }
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: indexFileURL, options: .atomic)
        } catch {
            print("Failed to save session index: \(error)")
        }
    }

    private func migrateLegacyHistoryIfNeeded() {
        guard !fileManager.fileExists(atPath: indexFileURL.path) else { return }

        for key in legacyKeys {
            guard let data = userDefaults.data(forKey: key),
                  let sessions = try? JSONDecoder().decode([ChatSession].self, from: data),
                  !sessions.isEmpty else {
                continue
            }

            ensureBaseDirectory()
            for session in sessions {
                saveSession(session)
            }
            saveIndex(from: sessions.sorted(by: { $0.date > $1.date }))
            telemetry.record(.legacyHistoryMigrated(provider: provider, sessionCount: sessions.count))
            return
        }
    }

    private func loadIndexItems() -> [ChatSessionIndexItem] {
        ensureBaseDirectory()
        guard let data = try? Data(contentsOf: indexFileURL),
              let items = try? JSONDecoder().decode([ChatSessionIndexItem].self, from: data) else {
            return []
        }
        return items.sorted(by: { $0.date > $1.date })
    }

    private var baseDirectoryURL: URL {
        let root = rootDirectoryOverride ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return root
            .appendingPathComponent("ChatSessions", isDirectory: true)
            .appendingPathComponent(provider.rawValue, isDirectory: true)
    }

    private var indexFileURL: URL {
        baseDirectoryURL.appendingPathComponent("index.json")
    }

    private func sessionFileURL(for id: String) -> URL {
        baseDirectoryURL.appendingPathComponent("\(id).json")
    }

    private func ensureBaseDirectory() {
        guard !fileManager.fileExists(atPath: baseDirectoryURL.path) else { return }
        do {
            try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
        } catch {
            print("Failed to create chat session directory: \(error)")
        }
    }
}
