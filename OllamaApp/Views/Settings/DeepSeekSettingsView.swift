import SwiftUI

struct DeepSeekSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("DeepSeekBaseURL") private var baseURL: String = "https://api.deepseek.com"
    @State private var savedApiKey: String = ""
    @State private var apiKeyInput: String = ""

    private var keychainService: String {
        Bundle.main.bundleIdentifier ?? "OllamaApp"
    }

    private var maskedSavedApiKey: String? {
        let trimmed = savedApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    Button("保存") {
                        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            _ = KeychainStore.shared.set(trimmed, service: keychainService, account: "deepseek_api_key")
                            savedApiKey = trimmed
                            apiKeyInput = ""
                        }
                        dismiss()
                    }

                    Button("清除 API Key") {
                        _ = KeychainStore.shared.delete(service: keychainService, account: "deepseek_api_key")
                        savedApiKey = ""
                        apiKeyInput = ""
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
                apiKeyInput = ""
            }
        }
    }
}
