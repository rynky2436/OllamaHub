import SwiftUI

@Observable
final class MenuBarViewModel {
    var ollamaRunning = false
    var runningModels: [RunningModel] = []

    func refresh() async {
        ollamaRunning = await OllamaService.shared.isRunning()
        if ollamaRunning {
            do {
                runningModels = try await OllamaService.shared.listRunning()
            } catch {
                runningModels = []
            }
        } else {
            runningModels = []
        }
    }
}

@main
struct OllamaHubApp: App {
    @State private var menuVM = MenuBarViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 900, height: 700)

        WindowGroup("Chat", id: "chat") {
            ChatView()
        }
        .defaultSize(width: 700, height: 600)

        MenuBarExtra {
            VStack(alignment: .leading, spacing: 0) {
                // Status
                HStack(spacing: 6) {
                    Circle()
                        .fill(menuVM.ollamaRunning ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(menuVM.ollamaRunning ? "Ollama Running" : "Ollama Stopped")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                if !menuVM.runningModels.isEmpty {
                    Divider()
                    Text("Loaded Models")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)

                    ForEach(menuVM.runningModels) { model in
                        HStack {
                            Text(model.name)
                                .font(.callout)
                            Spacer()
                            Text(formatBytes(model.sizeVram))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                }

                Divider()

                Button("Open OllamaHub") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    if let window = NSApplication.shared.windows.first(where: { $0.title == "OllamaHub" || $0.isKeyWindow }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Button("New Chat...") {
                    if let url = URL(string: "ollamahub://chat") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider()

                Button("Quit OllamaHub") {
                    NSApplication.shared.terminate(nil)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .frame(width: 250)
            .task {
                await menuVM.refresh()
            }
        } label: {
            Image(systemName: "cube.box")
        }
        .menuBarExtraStyle(.window)
    }
}
