import SwiftUI

@Observable
final class BenchmarkViewModel {
    var prompt = "Explain quantum computing in 3 sentences."
    var installedModels: [LocalModel] = []
    var selectedModels: Set<String> = []
    var results: [BenchmarkResult] = []
    var isRunning = false
    var currentModel = ""
    var progress = 0
    var total = 0
    var error: String?

    func loadModels() async {
        do {
            installedModels = try await OllamaService.shared.fetchInstalledModels()
        } catch {}
    }

    func toggleModel(_ name: String) {
        if selectedModels.contains(name) {
            selectedModels.remove(name)
        } else {
            selectedModels.insert(name)
        }
    }

    func selectAll() {
        selectedModels = Set(installedModels.map { $0.name })
    }

    func selectNone() {
        selectedModels.removeAll()
    }

    func run() async {
        guard !selectedModels.isEmpty else { return }
        let models = installedModels.filter { selectedModels.contains($0.name) }

        isRunning = true
        results = []
        error = nil
        total = models.count
        progress = 0

        for model in models {
            currentModel = model.name
            do {
                let result = try await OllamaService.shared.benchmark(
                    model: model.name,
                    prompt: prompt
                )
                results.append(result)
            } catch {
                results.append(BenchmarkResult(
                    modelName: model.name,
                    output: "Error: \(error.localizedDescription)",
                    totalDuration: 0, loadDuration: 0,
                    promptEvalCount: 0, promptEvalDuration: 0,
                    evalCount: 0, evalDuration: 0, vramBytes: 0
                ))
            }
            progress += 1
        }

        currentModel = ""
        isRunning = false
    }

    func exportMarkdown() -> String {
        var md = "# OllamaHub Benchmark Results\n\n"
        md += "**Prompt:** \(prompt)\n\n"
        md += "| Model | Tokens/sec | Time to First Token | Total Time | Tokens | VRAM |\n"
        md += "|-------|-----------|--------------------:|----------:|-------:|-----:|\n"

        for r in results.sorted(by: { $0.tokensPerSecond > $1.tokensPerSecond }) {
            let tps = String(format: "%.1f", r.tokensPerSecond)
            let ttft = String(format: "%.2fs", r.timeToFirstToken)
            let total = String(format: "%.2fs", r.totalDuration)
            let vram = formatBenchBytes(r.vramBytes)
            md += "| \(r.modelName) | \(tps) | \(ttft) | \(total) | \(r.evalCount) | \(vram) |\n"
        }

        md += "\n---\n\n"
        for r in results {
            md += "### \(r.modelName)\n\n\(r.output)\n\n"
        }
        return md
    }
}

struct BenchmarkView: View {
    @State private var vm = BenchmarkViewModel()
    @State private var expandedResult: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Config bar
            HStack(spacing: 12) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.title2)
                Text("Benchmark")
                    .font(.title2.bold())
                Spacer()

                if !vm.results.isEmpty {
                    Button {
                        let md = vm.exportMarkdown()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(md, forType: .string)
                    } label: {
                        Label("Copy Results", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Prompt
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Prompt")
                            .font(.headline)
                        TextEditor(text: $vm.prompt)
                            .font(.body)
                            .frame(height: 60)
                            .padding(4)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(8)
                    }

                    // Model selection
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Models")
                                .font(.headline)
                            Spacer()
                            Button("All") { vm.selectAll() }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .foregroundStyle(.blue)
                            Text("/")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("None") { vm.selectNone() }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }

                        FlowLayout(spacing: 6) {
                            ForEach(vm.installedModels) { model in
                                Button {
                                    vm.toggleModel(model.name)
                                } label: {
                                    Text(model.name)
                                        .font(.caption.monospaced())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(vm.selectedModels.contains(model.name) ? .blue : .blue.opacity(0.1))
                                        .foregroundStyle(vm.selectedModels.contains(model.name) ? .white : .blue)
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Run button
                    HStack {
                        if vm.isRunning {
                            ProgressView(value: Double(vm.progress), total: Double(vm.total))
                                .frame(width: 200)
                            Text("Running \(vm.currentModel)...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button {
                                Task { await vm.run() }
                            } label: {
                                Label("Run Benchmark", systemImage: "play.fill")
                                    .frame(width: 160)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(vm.selectedModels.isEmpty)
                        }
                    }

                    // Results
                    if !vm.results.isEmpty {
                        Divider()

                        Text("Results")
                            .font(.headline)

                        // Results table
                        resultsTable

                        Divider()

                        Text("Outputs")
                            .font(.headline)

                        ForEach(vm.results) { result in
                            outputCard(result)
                        }
                    }
                }
                .padding(20)
            }
        }
        .task { await vm.loadModels() }
    }

    private var resultsTable: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                Text("Model").frame(width: 180, alignment: .leading)
                Text("tok/s").frame(width: 70, alignment: .trailing)
                Text("TTFT").frame(width: 70, alignment: .trailing)
                Text("Total").frame(width: 70, alignment: .trailing)
                Text("Tokens").frame(width: 60, alignment: .trailing)
                Text("Prompt tok/s").frame(width: 90, alignment: .trailing)
                Text("VRAM").frame(width: 80, alignment: .trailing)
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            let sorted = vm.results.sorted { $0.tokensPerSecond > $1.tokensPerSecond }
            let best = sorted.first?.tokensPerSecond ?? 0

            ForEach(sorted) { result in
                HStack(spacing: 0) {
                    Text(result.modelName)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .frame(width: 180, alignment: .leading)

                    HStack(spacing: 4) {
                        Text(String(format: "%.1f", result.tokensPerSecond))
                        if result.tokensPerSecond == best && vm.results.count > 1 {
                            Image(systemName: "crown.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                    }
                    .font(.callout.monospaced().bold())
                    .foregroundStyle(result.tokensPerSecond == best && vm.results.count > 1 ? .green : .primary)
                    .frame(width: 70, alignment: .trailing)

                    Text(String(format: "%.2fs", result.timeToFirstToken))
                        .font(.callout.monospaced())
                        .frame(width: 70, alignment: .trailing)

                    Text(String(format: "%.2fs", result.totalDuration))
                        .font(.callout.monospaced())
                        .frame(width: 70, alignment: .trailing)

                    Text("\(result.evalCount)")
                        .font(.callout.monospaced())
                        .frame(width: 60, alignment: .trailing)

                    Text(String(format: "%.1f", result.promptTokensPerSecond))
                        .font(.callout.monospaced())
                        .frame(width: 90, alignment: .trailing)

                    Text(formatBenchBytes(result.vramBytes))
                        .font(.callout.monospaced())
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                if result.id != sorted.last?.id {
                    Divider().padding(.leading, 12)
                }
            }
        }
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func outputCard(_ result: BenchmarkResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(result.modelName)
                    .font(.callout.bold().monospaced())
                Spacer()
                Text(String(format: "%.1f tok/s", result.tokensPerSecond))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(result.output)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Flow Layout for model chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var maxHeight: CGFloat = 0
        var rowMaxHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowMaxHeight + spacing
                rowMaxHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowMaxHeight = max(rowMaxHeight, size.height)
            x += size.width + spacing
            maxHeight = max(maxHeight, y + rowMaxHeight)
        }
        return (CGSize(width: width, height: maxHeight), positions)
    }
}

func formatBenchBytes(_ bytes: Int64) -> String {
    if bytes == 0 { return "—" }
    let gb = Double(bytes) / 1_073_741_824
    if gb >= 1 { return String(format: "%.1f GB", gb) }
    let mb = Double(bytes) / 1_048_576
    return String(format: "%.0f MB", mb)
}
