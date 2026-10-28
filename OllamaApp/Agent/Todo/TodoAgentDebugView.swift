//
//  TodoAgentDebugView.swift
//  OllamaApp
//
//  Created by maochengfang on 2026/10/27.
//

import SwiftUI

@MainActor
final class TodoAgentDebugViewModel: ObservableObject {
    struct Line: Identifiable {
        let id = UUID()
        let role: String
        let text: String
    }

    @Published var input: String = ""
    @Published var lines: [Line] = []
    @Published var isRunning: Bool = false
    @Published var todos: [TodoItem] = []
    @Published var streamingText: String = ""

    private let agent = TodoAgent()

    func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRunning else { return }

        input = ""
        lines.append(Line(role: "user", text: text))
        isRunning = true
        defer {
            isRunning = false
            todos = TodoStore.shared.list()
        }

        do {
            let reply = try await agent.send(text) { [weak self] piece in
                MainActor.assumeIsolated { self?.streamingText += piece }
            }
            streamingText = ""
            lines.append(Line(role: "agent", text: reply))
        } catch {
            streamingText = ""
            lines.append(Line(role: "error", text: error.localizedDescription))
        }
    }

    func reset() {
        agent.reset()
        lines.removeAll()
        todos = TodoStore.shared.list()
    }

    func toggle(_ todo: TodoItem) {
        TodoStore.shared.toggle(key: todo.id)
        refreshTodos()
    }

    func delete(_ todo: TodoItem) {
        TodoStore.shared.delete(key: todo.id)
        refreshTodos()
    }

    func refreshTodos() {
        todos = TodoStore.shared.list()
    }
}

struct TodoAgentDebugView: View {
    @StateObject private var viewModel = TodoAgentDebugViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDeletion: TodoItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                conversation
                Divider()
                inputBar
            }
            .navigationTitle("待办 Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("重置") { viewModel.reset() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .task {
                viewModel.todos = TodoStore.shared.list()
            }
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if viewModel.lines.isEmpty {
                    Text("试试：「帮我记一下明天交周报，然后列出所有待办」")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 24)
                }

                ForEach(viewModel.lines) { line in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(label(for: line.role))
                            .font(.caption)
                            .foregroundColor(color(for: line.role))
                        lineText(for: line)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(color(for: line.role).opacity(0.08))
                    .cornerRadius(10)
                }

                if !viewModel.streamingText.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(label(for: "agent"))
                            .font(.caption)
                            .foregroundColor(color(for: "agent"))
                        Text(viewModel.streamingText)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(color(for: "agent").opacity(0.08))
                    .cornerRadius(10)
                }

                if !viewModel.todos.isEmpty {
                    todoPreview
                }

                Color.clear
                    .frame(height: 1)
                    .id("bottom")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
            .onChange(of: viewModel.lines.count) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: viewModel.streamingText) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var todoPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("本地待办（TodoStore）")
                .font(.caption)
                .foregroundColor(.secondary)
            ForEach(viewModel.todos) { todo in
                HStack(spacing: 8) {
                    Button {
                        viewModel.toggle(todo)
                    } label: {
                        Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(todo.isDone ? .green : .secondary)
                    }
                    .buttonStyle(.plain)

                    Text(todo.title)
                        .font(.footnote)
                        .strikethrough(todo.isDone)
                        .foregroundColor(todo.isDone ? .secondary : .primary)

                    Spacer()

                    Button(role: .destructive) {
                        pendingDeletion = todo
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.blue.opacity(0.06))
        .cornerRadius(10)
        .confirmationDialog(
            "确定删除「\(pendingDeletion?.title ?? "")」？",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let todo = pendingDeletion {
                    viewModel.delete(todo)
                }
                pendingDeletion = nil
            }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("输入待办指令…", text: $viewModel.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(viewModel.isRunning)

            Button {
                Task { await viewModel.send() }
            } label: {
                if viewModel.isRunning {
                    ProgressView()
                } else {
                    Image(systemName: "paperplane.fill")
                }
            }
            .disabled(viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isRunning)
        }
        .padding()
    }

    private func label(for role: String) -> String {
        switch role {
        case "user": return "你"
        case "agent": return "Agent"
        default: return "错误"
        }
    }

    @ViewBuilder
    private func lineText(for line: TodoAgentDebugViewModel.Line) -> some View {
        if line.role == "agent" {
            MarkdownBlockView(text: line.text, foreground: .primary)
                .textSelection(.enabled)
        } else {
            Text(line.text)
                .font(.body)
                .textSelection(.enabled)
        }
    }

    private func color(for role: String) -> Color {
        switch role {
        case "user": return .blue
        case "agent": return .green
        default: return .red
        }
    }
}
