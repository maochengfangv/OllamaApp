//
//  ContentView.swift
//  OllamaApp
//
//  Created by maochengfang on 2026/3/27.
//

import SwiftUI
import UIKit

struct ChatView: View {
    let provider: LLMProvider
    @ObservedObject var manager: OllamaManager
    @State private var prompt: String = ""
    @AppStorage("DeepSeekWebEnabled") private var isWebEnabled: Bool = false
    @AppStorage private var selectedModel: String
    @State private var showDeepSeekSettings: Bool = false
    @FocusState private var isPromptFocused: Bool
    @FocusState private var isModelFocused: Bool

    init(provider: LLMProvider, manager: OllamaManager) {
        self.provider = provider
        self.manager = manager
        _selectedModel = AppStorage(wrappedValue: provider.defaultModel, provider.selectedModelKey)
    }

    private var accentColor: Color {
        provider == .ollama ? .blue : .green
    }

    private var effectiveWebEnabled: Bool {
        provider.supportsWebEnhancement ? isWebEnabled : false
    }

    var body: some View {
        VStack {
            HStack {
                TextField(provider.modelPlaceholder, text: $selectedModel)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($isModelFocused)
                    .disabled(manager.isGenerating)
                    .allowsHitTesting(!manager.isGenerating)

                if provider.supportsWebEnhancement {
                    Toggle(isOn: $isWebEnabled) {
                        Text("联网")
                    }
                    .toggleStyle(.switch)
                    .labelStyle(.titleOnly)
                    .fixedSize()
                    .disabled(manager.isGenerating)

                    Button(action: {
                        showDeepSeekSettings = true
                    }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(.horizontal)

            ScrollViewReader { proxy in
                List {
                    ForEach(manager.messages) { message in
                        ChatMessageRow(
                            message: message,
                            isGenerating: manager.isGenerating,
                            onResend: message.role == .user ? {
                                Task {
                                    await manager.resend(
                                        messageId: message.id,
                                        model: selectedModel,
                                        webEnabled: effectiveWebEnabled
                                    )
                                }
                            } : nil
                        )
                        .id(message.id)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(PlainListStyle())
                .onChange(of: manager.messages) { _, _ in
                    scrollToBottom(using: proxy)
                }
                .onChange(of: manager.messages.last?.content) { _, _ in
                    scrollToBottom(using: proxy)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(10)
            .padding(.horizontal)

            HStack {
                TextField("Enter prompt...", text: $prompt)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disabled(manager.isGenerating)
                    .focused($isPromptFocused)
                    .allowsHitTesting(!manager.isGenerating)

                if manager.isGenerating {
                    Button(action: {
                        manager.stopGenerating()
                    }) {
                        Image(systemName: "stop.circle.fill")
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                } else {
                    Button(action: sendPrompt) {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(.white)
                            .padding(8)
                            .background(accentColor)
                            .clipShape(Circle())
                    }
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
        }
        .navigationTitle(manager.currentSessionId == nil ? provider.newChatTitle : "\(provider.displayName) Chat")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDeepSeekSettings) {
            DeepSeekSettingsView()
        }
        .onChange(of: manager.isGenerating) { _, isGenerating in
            if isGenerating {
                isPromptFocused = false
                isModelFocused = false
            }
        }
    }

    private func sendPrompt() {
        let currentPrompt = prompt
        Task {
            await manager.generate(prompt: currentPrompt, model: selectedModel, webEnabled: effectiveWebEnabled)
            prompt = ""
        }
    }

    private func scrollToBottom(using proxy: ScrollViewProxy) {
        if let lastId = manager.messages.last?.id {
            withAnimation {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }
}

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

struct ChatMessageRow: View {
    let message: ChatMessage
    let isGenerating: Bool
    let onResend: (() -> Void)?
    @State private var didCopy: Bool = false

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 50)
                bubble(background: Color.blue, foreground: .white)
                    .contextMenu {
                        if let onResend {
                            Button("重新发送", action: onResend)
                                .disabled(isGenerating)
                        }
                    }
            } else {
                bubble(background: Color.gray.opacity(0.15), foreground: .primary)
                Spacer(minLength: 50)
            }
        }
    }

    private func bubble(background: Color, foreground: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if message.role == .model, message.content.isEmpty, isGenerating {
                HStack(spacing: 4) {
                    Circle().frame(width: 6, height: 6).opacity(0.4)
                    Circle().frame(width: 6, height: 6).opacity(0.7)
                    Circle().frame(width: 6, height: 6).opacity(1.0)
                }
                .padding(12)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message.content)
                        .foregroundColor(foreground)

                    HStack {
                        Spacer()
                        Button(action: copyToClipboard) {
                            HStack(spacing: 6) {
                                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                                Text(didCopy ? "已复制" : "复制")
                            }
                            .font(.caption)
                            .foregroundColor(foreground.opacity(0.85))
                        }
                        .disabled(message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(12)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = message.content
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            didCopy = false
        }
    }
}
