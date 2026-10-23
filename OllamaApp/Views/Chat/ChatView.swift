import SwiftUI

struct ChatView: View {
    let provider: LLMProvider
    @ObservedObject var manager: OllamaManager
    @State private var prompt: String = ""
    @AppStorage("DeepSeekWebEnabled") private var isWebEnabled: Bool = false
    @AppStorage private var selectedModel: String
    @State private var showDeepSeekSettings: Bool = false
    @State private var showDebugPanel: Bool = false
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

                Button(action: {
                    showDebugPanel = true
                }) {
                    Image(systemName: "ladybug")
                        .foregroundColor(.primary)
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
        .sheet(isPresented: $showDebugPanel) {
            AIDebugPanelView(provider: provider, manager: manager)
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
