//
//  ContentView.swift
//  OllamaApp
//
//  Created by maochengfang on 2026/3/27.
//

import SwiftUI

struct ChatView: View {
    @ObservedObject var ollamaManager: OllamaManager
    @State private var prompt: String = ""
    @State private var selectedModel: String = "phi3"
    
    var body: some View {
        VStack {
            TextField("Model (e.g. llama3)", text: $selectedModel)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            ScrollViewReader { proxy in
                List {
                    ForEach(ollamaManager.messages) { message in
                        HStack {
                            if message.role == .user {
                                Spacer(minLength: 50)
                                Text(message.content)
                                    .padding(12)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            } else {
                                VStack(alignment: .leading) {
                                    if message.content.isEmpty && ollamaManager.isGenerating {
                                        HStack(spacing: 4) {
                                            Circle().frame(width: 6, height: 6).opacity(0.4)
                                            Circle().frame(width: 6, height: 6).opacity(0.7)
                                            Circle().frame(width: 6, height: 6).opacity(1.0)
                                        }
                                        .padding(12)
                                        .background(Color.gray.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                    } else {
                                        Text(message.content)
                                            .padding(12)
                                            .background(Color.gray.opacity(0.15))
                                            .foregroundColor(.primary)
                                            .clipShape(RoundedRectangle(cornerRadius: 16))
                                    }
                                }
                                Spacer(minLength: 50)
                            }
                        }
                        .id(message.id)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(PlainListStyle())
                .onChange(of: ollamaManager.messages) { _, _ in
                    if let lastId = ollamaManager.messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: ollamaManager.messages.last?.content) { _, _ in
                    if let lastId = ollamaManager.messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(10)
            .padding(.horizontal)
            
            HStack {
                TextField("Enter prompt...", text: $prompt)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disabled(ollamaManager.isGenerating)
                
                if ollamaManager.isGenerating {
                    Button(action: {
                        ollamaManager.stopGenerating()
                    }) {
                        Image(systemName: "stop.circle.fill")
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                } else {
                    Button(action: {
                        Task {
                            await ollamaManager.generate(prompt: prompt, model: selectedModel)
                            prompt = ""
                        }
                    }) {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.blue)
                            .clipShape(Circle())
                    }
                    .disabled(prompt.isEmpty)
                }
            }
            .padding()
        }
        .navigationTitle(ollamaManager.currentSessionId == nil ? "New Chat" : "Chat")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ContentView: View {
    @StateObject private var ollamaManager = OllamaManager()
    @State private var prompt: String = ""
    @State private var selectedModel: String = "phi3"
    @State private var showSidebar = false
    
    var body: some View {
        NavigationStack {
            // Sidebar for Chat History
            VStack(spacing: 3) {
                NavigationLink(destination: ChatView(ollamaManager: ollamaManager)
                    .onAppear {
                        ollamaManager.startNewChat()
                    }
                ) {
                    HStack {
                        Image(systemName: "square.and.pencil")
                        Text("New Chat")
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
                
                List {
                    Section(header: Text("History")) {
                        ForEach(ollamaManager.chatHistory) { session in
                            NavigationLink(destination: ChatView(ollamaManager: ollamaManager)
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
                }
                .navigationTitle("Chats")
            }
        }
    }
}
    

#Preview {
    ContentView()
}
