import SwiftUI

@Observable
final class AppViewModel {
    var models: [OllamaModel] = []
    var installedModels: [LocalModel] = []
    var installedNames: Set<String> = []
    var isLoading = false
    var errorMessage: String?
    var searchText = ""
    var ollamaRunning = false
    var downloadStates: [String: DownloadState] = [:]
    var selectedTab: ModelTab = .all
    var selectedSizes: [String: String] = [:]
    var modelToDelete: LocalModel?
    var deleteError: String?
    var detailModel: OllamaModel?

    private var pullTasks: [String: Task<Void, Never>] = [:]

    var filteredModels: [OllamaModel] {
        var result = models

        switch selectedTab {
        case .all: break
        case .local: result = result.filter { !$0.localSizes.isEmpty }
        case .cloud: result = result.filter { $0.hasCloud }
        case .myModels: return []
        case .chat: return []
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                $0.description.lowercased().contains(query)
            }
        }

        return result
    }

    var filteredInstalledModels: [LocalModel] {
        if searchText.isEmpty { return installedModels }
        let query = searchText.lowercased()
        return installedModels.filter { $0.name.lowercased().contains(query) }
    }

    func isInstalled(_ model: OllamaModel) -> Bool {
        installedNames.contains(model.name)
    }

    func selectedSize(for model: OllamaModel) -> String? {
        selectedSizes[model.name]
    }

    func selectSize(_ size: String, for model: OllamaModel) {
        if selectedSizes[model.name] == size {
            selectedSizes[model.name] = nil
        } else {
            selectedSizes[model.name] = size
        }
    }

    func pullTag(for model: OllamaModel) -> String {
        if let selected = selectedSizes[model.name] {
            return "\(model.name):\(selected)"
        }
        return model.name
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        async let running = OllamaService.shared.isRunning()
        async let library = OllamaService.shared.fetchLibraryModels()

        ollamaRunning = await running

        do {
            models = try await library
        } catch {
            errorMessage = error.localizedDescription
        }

        if ollamaRunning {
            await refreshInstalled()
        }

        isLoading = false
    }

    func refreshInstalled() async {
        do {
            let local = try await OllamaService.shared.fetchInstalledModels()
            installedModels = local.sorted { $0.name < $1.name }
            installedNames = Set(local.map { $0.baseName })
        } catch {}
    }

    func deleteModel(_ model: LocalModel) async {
        do {
            try await OllamaService.shared.deleteModel(name: model.name)
            await refreshInstalled()
            deleteError = nil
        } catch {
            deleteError = error.localizedDescription
        }
    }

    func pullModel(_ model: OllamaModel) {
        let tag = pullTag(for: model)
        let key = tag

        guard downloadStates[key] == nil || downloadStates[key] == .idle ||
              downloadStates[key] == .complete else { return }

        if case .failed = downloadStates[key] {
            pullTasks[key]?.cancel()
        }

        downloadStates[key] = .pulling(progress: 0, status: "Starting...")

        pullTasks[key] = Task {
            do {
                try await OllamaService.shared.pullModel(name: tag) { [weak self] progress in
                    Task { @MainActor in
                        guard let self else { return }
                        if progress.status == "success" {
                            self.downloadStates[key] = .complete
                            self.installedNames.insert(model.name)
                        } else if let total = progress.total, total > 0,
                                  let completed = progress.completed {
                            let pct = Double(completed) / Double(total)
                            let completedMB = Double(completed) / 1_000_000
                            let totalMB = Double(total) / 1_000_000
                            let status: String
                            if totalMB >= 1000 {
                                status = String(format: "%.1f / %.1f GB", completedMB / 1000, totalMB / 1000)
                            } else {
                                status = String(format: "%.0f / %.0f MB", completedMB, totalMB)
                            }
                            self.downloadStates[key] = .pulling(progress: pct, status: status)
                        } else {
                            self.downloadStates[key] = .pulling(
                                progress: 0,
                                status: progress.status.prefix(40).description
                            )
                        }
                    }
                }
                await MainActor.run {
                    if downloadStates[key] != .complete {
                        downloadStates[key] = .complete
                        installedNames.insert(model.name)
                    }
                }
                await refreshInstalled()
            } catch is CancellationError {
                await MainActor.run { downloadStates[key] = .idle }
            } catch {
                await MainActor.run {
                    downloadStates[key] = .failed(error.localizedDescription)
                }
            }
        }
    }

    func cancelPull(_ model: OllamaModel) {
        let key = pullTag(for: model)
        pullTasks[key]?.cancel()
        pullTasks[key] = nil
        downloadStates[key] = .idle
    }
}

// MARK: - Content View

struct ContentView: View {
    @State private var vm = AppViewModel()
    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if vm.isLoading {
                Spacer()
                ProgressView("Loading models...")
                Spacer()
            } else if vm.selectedTab == .myModels {
                myModelsList
            } else if vm.selectedTab == .chat {
                ChatView()
            } else if let error = vm.errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(error)
                        .foregroundStyle(.secondary)
                    Button("Retry") { Task { await vm.load() } }
                }
                Spacer()
            } else if vm.filteredModels.isEmpty {
                Spacer()
                Text("No models found")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                modelList
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .task { await vm.load() }
        .sheet(item: $vm.detailModel) { model in
            ModelDetailView(model: model, isInstalled: vm.isInstalled(model))
        }
        .alert("Delete Model", isPresented: Binding(
            get: { vm.modelToDelete != nil },
            set: { if !$0 { vm.modelToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { vm.modelToDelete = nil }
            Button("Delete", role: .destructive) {
                if let model = vm.modelToDelete {
                    Task { await vm.deleteModel(model) }
                    vm.modelToDelete = nil
                }
            }
        } message: {
            if let model = vm.modelToDelete {
                Text("Are you sure you want to delete \(model.name)? This will free \(formatBytes(model.size)).")
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "cube.box")
                .font(.title2)
                .foregroundStyle(.primary)
            Text("OllamaHub")
                .font(.title2.bold())

            Picker("", selection: $vm.selectedTab) {
                ForEach(ModelTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 370)

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(vm.ollamaRunning ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(vm.ollamaRunning ? "Ollama Running" : "Ollama Not Running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search models...", text: $vm.searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 200)
                if !vm.searchText.isEmpty {
                    Button {
                        vm.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary)
            .cornerRadius(8)

            Button {
                Task { await vm.load() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var modelList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(vm.filteredModels) { model in
                    ModelRowView(
                        model: model,
                        isInstalled: vm.isInstalled(model),
                        downloadState: vm.downloadStates[vm.pullTag(for: model)] ?? .idle,
                        ollamaRunning: vm.ollamaRunning,
                        selectedSize: vm.selectedSize(for: model),
                        showCloudSizes: vm.selectedTab == .cloud,
                        onSelectSize: { size in vm.selectSize(size, for: model) },
                        onPull: { vm.pullModel(model) },
                        onCancel: { vm.cancelPull(model) }
                    )
                    .onTapGesture { vm.detailModel = model }
                    Divider()
                        .padding(.leading, 20)
                }
            }
        }
    }

    // MARK: - My Models Tab

    private var myModelsList: some View {
        Group {
            if !vm.ollamaRunning {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Ollama is not running")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if vm.filteredInstalledModels.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(vm.searchText.isEmpty ? "No models installed" : "No matching models")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    // Total storage summary
                    HStack {
                        let totalSize = vm.filteredInstalledModels.reduce(Int64(0)) { $0 + $1.size }
                        Text("\(vm.filteredInstalledModels.count) models")
                            .font(.subheadline.bold())
                        Text("using \(formatBytes(totalSize))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                    LazyVStack(spacing: 0) {
                        ForEach(vm.filteredInstalledModels) { model in
                            InstalledModelRow(
                                model: model,
                                onDelete: { vm.modelToDelete = model }
                            )
                            Divider()
                                .padding(.leading, 20)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Installed Model Row

struct InstalledModelRow: View {
    let model: LocalModel
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(.headline)

                HStack(spacing: 12) {
                    Label(formatBytes(model.size), systemImage: "internaldrive")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label(model.digest.prefix(12).description, systemImage: "number")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
                    .frame(width: 100)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Helpers

func formatBytes(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_073_741_824
    if gb >= 1 {
        return String(format: "%.1f GB", gb)
    }
    let mb = Double(bytes) / 1_048_576
    return String(format: "%.0f MB", mb)
}
