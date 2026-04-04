import SwiftUI

struct ModelRowView: View {
    let model: OllamaModel
    let isInstalled: Bool
    let downloadState: DownloadState
    let ollamaRunning: Bool
    let selectedSize: String?
    let showCloudSizes: Bool
    let onSelectSize: (String) -> Void
    let onPull: () -> Void
    let onCancel: () -> Void

    private var displaySizes: [String] {
        if showCloudSizes {
            return model.sizes.filter { $0.lowercased() == "cloud" }
        } else {
            return model.localSizes
        }
    }

    private var pullLabel: String {
        if let size = selectedSize {
            return "Pull :\(size)"
        }
        return "Pull"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Model info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(model.name)
                        .font(.headline)

                    if isInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    if let cap = model.capability {
                        Text(cap)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.indigo.opacity(0.1))
                            .foregroundStyle(.indigo)
                            .cornerRadius(4)
                    }

                    if model.hasCloud {
                        Text("cloud")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.cyan.opacity(0.1))
                            .foregroundStyle(.cyan)
                            .cornerRadius(4)
                    }
                }

                Text(model.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    // Selectable size badges
                    if !displaySizes.isEmpty {
                        ForEach(displaySizes.prefix(6), id: \.self) { size in
                            Button {
                                onSelectSize(size)
                            } label: {
                                Text(size.uppercased())
                                    .font(.caption2.monospaced().bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(selectedSize == size ? .blue : .blue.opacity(0.1))
                                    .foregroundStyle(selectedSize == size ? .white : .blue)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                        if displaySizes.count > 6 {
                            Text("+\(displaySizes.count - 6)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                        .frame(width: 4)

                    // Pull count
                    Label(model.pullCount, systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Updated
                    Text(model.updated)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 2)
            }

            Spacer()

            // Download button / progress
            downloadSection
                .frame(width: 180)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var downloadSection: some View {
        switch downloadState {
        case .idle:
            if isInstalled && selectedSize == nil {
                Button {
                    onPull()
                } label: {
                    Label("Update", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button {
                    onPull()
                } label: {
                    Label(pullLabel, systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!ollamaRunning)
            }

        case .pulling(let progress, let status):
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                HStack {
                    Text(status)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.red)
            }

        case .complete:
            Label("Pulled", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)

        case .failed(let error):
            VStack(alignment: .trailing, spacing: 4) {
                Label("Failed", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Retry") { onPull() }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
    }
}
