import SwiftUI

@Observable
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var inputText = ""
    var selectedModel = ""
    var installedModels: [LocalModel] = []
    var isGenerating = false
    var error: String?

    private var chatTask: Task<Void, Never>?

    func loadModels() async {
        do {
            installedModels = try await OllamaService.shared.fetchInstalledModels()
            if selectedModel.isEmpty, let first = installedModels.first {
                selectedModel = first.name
            }
        } catch {}
    }

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !selectedModel.isEmpty else { return }

        inputText = ""
        error = nil
        messages.append(ChatMessage(role: "user", content: text))
        messages.append(ChatMessage(role: "assistant", content: ""))
        isGenerating = true

        let history = messages.dropLast().map { (role: $0.role, content: $0.content) }

        chatTask = Task {
            do {
                try await OllamaService.shared.chat(
                    model: selectedModel,
                    messages: Array(history)
                ) { [weak self] token in
                    Task { @MainActor in
                        guard let self, !self.messages.isEmpty else { return }
                        self.messages[self.messages.count - 1].content += token
                    }
                }
            } catch is CancellationError {
                // User cancelled
            } catch {
                await MainActor.run { self.error = error.localizedDescription }
            }
            await MainActor.run { self.isGenerating = false }
        }
    }

    func stop() {
        chatTask?.cancel()
        chatTask = nil
        isGenerating = false
    }

    func clear() {
        stop()
        messages.removeAll()
        error = nil
    }
}

struct ChatView: View {
    @State private var vm = ChatViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.title2)
                Text("Chat")
                    .font(.title2.bold())

                Picker("Model", selection: $vm.selectedModel) {
                    ForEach(vm.installedModels) { model in
                        Text(model.name).tag(model.name)
                    }
                }
                .frame(width: 250)

                Spacer()

                Button {
                    vm.clear()
                } label: {
                    Label("New Chat", systemImage: "plus.circle")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            // Messages
            if vm.messages.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("Start a conversation")
                        .foregroundStyle(.secondary)
                    if !vm.selectedModel.isEmpty {
                        Text("Using \(vm.selectedModel)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(vm.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(20)
                    }
                    .onChange(of: vm.messages.last?.content) {
                        if let last = vm.messages.last {
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            if let error = vm.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
            }

            Divider()

            // Input
            HStack(spacing: 12) {
                TextField("Message...", text: $vm.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .onSubmit {
                        if !NSEvent.modifierFlags.contains(.shift) {
                            vm.send()
                        }
                    }

                if vm.isGenerating {
                    Button {
                        vm.stop()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        vm.send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.selectedModel.isEmpty)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 600, minHeight: 400)
        .task { await vm.loadModels() }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 80) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content.isEmpty ? " " : message.content)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isUser ? Color.blue : Color(.controlBackgroundColor))
                    .foregroundStyle(isUser ? .white : .primary)
                    .cornerRadius(16)
            }
            if !isUser { Spacer(minLength: 80) }
        }
    }
}
