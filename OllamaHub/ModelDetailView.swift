import SwiftUI

@Observable
final class ModelDetailViewModel {
    var tags: [ModelTag] = []
    var modelInfo: ModelInfo?
    var isLoadingTags = false
    var isLoadingInfo = false
    var tagError: String?
    var downloadStates: [String: DownloadState] = [:]

    private var pullTasks: [String: Task<Void, Never>] = [:]

    func loadTags(for model: OllamaModel) async {
        isLoadingTags = true
        tagError = nil
        do {
            tags = try await OllamaService.shared.fetchModelTags(name: model.name)
        } catch {
            tagError = error.localizedDescription
        }
        isLoadingTags = false
    }

    func loadInfo(for modelName: String) async {
        isLoadingInfo = true
        do {
            modelInfo = try await OllamaService.shared.showModel(name: modelName)
        } catch {
            modelInfo = nil
        }
        isLoadingInfo = false
    }

    func pullTag(_ tag: ModelTag) {
        let key = tag.name
        guard downloadStates[key] == nil || downloadStates[key] == .idle else { return }

        downloadStates[key] = .pulling(progress: 0, status: "Starting...")

        pullTasks[key] = Task {
            do {
                try await OllamaService.shared.pullModel(name: tag.name) { [weak self] progress in
                    Task { @MainActor in
                        guard let self else { return }
                        if progress.status == "success" {
                            self.downloadStates[key] = .complete
                        } else if let total = progress.total, total > 0,
                                  let completed = progress.completed {
                            let pct = Double(completed) / Double(total)
                            let cMB = Double(completed) / 1_000_000
                            let tMB = Double(total) / 1_000_000
                            let status = tMB >= 1000
                                ? String(format: "%.1f / %.1f GB", cMB / 1000, tMB / 1000)
                                : String(format: "%.0f / %.0f MB", cMB, tMB)
                            self.downloadStates[key] = .pulling(progress: pct, status: status)
                        } else {
                            self.downloadStates[key] = .pulling(progress: 0, status: progress.status.prefix(30).description)
                        }
                    }
                }
                await MainActor.run {
                    if downloadStates[key] != .complete { downloadStates[key] = .complete }
                }
            } catch is CancellationError {
                await MainActor.run { downloadStates[key] = .idle }
            } catch {
                await MainActor.run { downloadStates[key] = .failed(error.localizedDescription) }
            }
        }
    }
}

struct ModelDetailView: View {
    let model: OllamaModel
    let isInstalled: Bool
    @State private var vm = ModelDetailViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(model.name)
                            .font(.title.bold())
                        if isInstalled {
                            Label("Installed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.callout)
                        }
                        if let cap = model.capability {
                            Text(cap)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.indigo.opacity(0.1))
                                .foregroundStyle(.indigo)
                                .cornerRadius(6)
                        }
                        if model.hasCloud {
                            Text("cloud")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.cyan.opacity(0.1))
                                .foregroundStyle(.cyan)
                                .cornerRadius(6)
                        }
                    }
                    Text(model.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        Label(model.pullCount, systemImage: "arrow.down.circle")
                        Text(model.updated)
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            // Model info (if installed)
            if let info = vm.modelInfo, let details = info.details {
                HStack(spacing: 20) {
                    InfoChip(label: "Family", value: details.family ?? "—")
                    InfoChip(label: "Parameters", value: details.parameterSize ?? "—")
                    InfoChip(label: "Quantization", value: details.quantizationLevel ?? "—")
                    InfoChip(label: "Format", value: details.format ?? "—")
                    if let caps = info.capabilities, !caps.isEmpty {
                        InfoChip(label: "Capabilities", value: caps.joined(separator: ", "))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                Divider()
            }

            // Tags list
            if vm.isLoadingTags {
                Spacer()
                ProgressView("Loading tags...")
                Spacer()
            } else if let error = vm.tagError {
                Spacer()
                Text(error).foregroundStyle(.secondary)
                Spacer()
            } else {
                HStack {
                    Text("Available Tags")
                        .font(.headline)
                    Spacer()
                    Text("\(vm.tags.count) tags")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 4)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.tags) { tag in
                            TagRow(
                                tag: tag,
                                state: vm.downloadStates[tag.name] ?? .idle,
                                onPull: { vm.pullTag(tag) }
                            )
                            Divider().padding(.leading, 20)
                        }
                    }
                }
            }
        }
        .frame(width: 700, height: 500)
        .task {
            await vm.loadTags(for: model)
            if isInstalled {
                await vm.loadInfo(for: model.name)
            }
        }
    }
}

struct TagRow: View {
    let tag: ModelTag
    let state: DownloadState
    let onPull: () -> Void

    var body: some View {
        HStack {
            Text(tag.tag)
                .font(.body.monospaced())
            Spacer()
            Text(tag.size)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)

            Group {
                switch state {
                case .idle:
                    Button("Pull") { onPull() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                case .pulling(let p, let s):
                    HStack(spacing: 6) {
                        ProgressView(value: p)
                            .frame(width: 80)
                        Text(s)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                case .complete:
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                case .failed:
                    Button("Retry") { onPull() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .frame(width: 160, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

struct InfoChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.monospaced().bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary)
        .cornerRadius(6)
    }
}
