import SwiftUI

struct DeepSeekSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("DeepSeekBaseURL") private var baseURL: String = "https://api.deepseek.com"
    @AppStorage(AIMemorySettings.enabledKey) private var memoryEnabled: Bool = true
    @AppStorage(AIEmbeddingEndpoint.baseURLKey) private var embeddingBaseURL: String = AIEmbeddingEndpoint.defaultBaseURL
    @AppStorage("EmbeddingModel") private var embeddingModel: String = AIEmbeddingModel.defaultModel
    @State private var savedApiKey: String = ""
    @State private var apiKeyInput: String = ""
    @State private var savedEmbeddingApiKey: String = ""
    @State private var embeddingApiKeyInput: String = ""

    private var keychainService: String {
        Bundle.main.bundleIdentifier ?? "OllamaApp"
    }

    private var maskedSavedApiKey: String? {
        let trimmed = savedApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "••••" + trimmed.suffix(4)
    }

    private var maskedSavedEmbeddingApiKey: String? {
        let trimmed = savedEmbeddingApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "••••" + trimmed.suffix(4)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("DeepSeek") {
                    TextField("Base URL", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    if let maskedSavedApiKey {
                        Text("已保存：\(maskedSavedApiKey)")
                            .foregroundColor(.secondary)
                    }

                    SecureField("API Key（留空则不修改）", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }

                Section {
                    Toggle("长期记忆 (RAG Memory)", isOn: $memoryEnabled)
                } header: {
                    Text("AI 能力")
                } footer: {
                    Text("开启后，对话内容会经向量化后本地存储，并在后续对话中召回相关记忆。向量化需联网调用 Embedding 接口。")
                }

                Section {
                    TextField("Embedding Base URL", text: $embeddingBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    TextField("Embedding Model", text: $embeddingModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    if let maskedSavedEmbeddingApiKey {
                        Text("已保存：\(maskedSavedEmbeddingApiKey)")
                            .foregroundColor(.secondary)
                    }

                    SecureField("Embedding API Key（留空则不修改）", text: $embeddingApiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                } header: {
                    Text("Embedding (DashScope)")
                } footer: {
                    Text("推荐填写 DashScope 北京区 OpenAI 兼容地址，例如 https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/compatible-mode/v1，默认模型 text-embedding-v4。")
                }

                Section {
                    Button("保存") {
                        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            _ = KeychainStore.shared.set(trimmed, service: keychainService, account: "deepseek_api_key")
                            savedApiKey = trimmed
                            apiKeyInput = ""
                        }
                        let embeddingTrimmed = embeddingApiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !embeddingTrimmed.isEmpty {
                            _ = KeychainStore.shared.set(embeddingTrimmed, service: keychainService, account: AIEmbeddingEndpoint.apiKeyAccount)
                            savedEmbeddingApiKey = embeddingTrimmed
                            embeddingApiKeyInput = ""
                        }
                        dismiss()
                    }

                    Button("清除 DeepSeek API Key") {
                        _ = KeychainStore.shared.delete(service: keychainService, account: "deepseek_api_key")
                        savedApiKey = ""
                        apiKeyInput = ""
                    }
                    .foregroundColor(.red)

                    Button("清除 Embedding API Key") {
                        _ = KeychainStore.shared.delete(service: keychainService, account: AIEmbeddingEndpoint.apiKeyAccount)
                        savedEmbeddingApiKey = ""
                        embeddingApiKeyInput = ""
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                savedApiKey = KeychainStore.shared.get(service: keychainService, account: "deepseek_api_key") ?? ""
                savedEmbeddingApiKey = KeychainStore.shared.get(service: keychainService, account: AIEmbeddingEndpoint.apiKeyAccount) ?? ""
                apiKeyInput = ""
                embeddingApiKeyInput = ""
            }
        }
    }
}
