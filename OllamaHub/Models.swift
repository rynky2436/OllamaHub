import Foundation

// MARK: - Ollama Library Models (scraped from ollama.com/library)

struct OllamaModel: Identifiable, Hashable {
    let id: String // same as name
    let name: String
    let description: String
    let pullCount: String
    let updated: String
    let capability: String?
    let sizes: [String]

    var localSizes: [String] { sizes.filter { $0.lowercased() != "cloud" } }
    var hasCloud: Bool { sizes.contains { $0.lowercased() == "cloud" } }
}

enum ModelTab: String, CaseIterable {
    case all = "All"
    case local = "Local"
    case cloud = "Cloud"
    case myModels = "My Models"
}

// MARK: - Local Ollama API Models

struct LocalModelsResponse: Codable {
    let models: [LocalModel]
}

struct LocalModel: Codable, Identifiable {
    let name: String
    let model: String
    let modifiedAt: String
    let size: Int64
    let digest: String

    var id: String { name }
    var baseName: String {
        name.contains(":") ? String(name.split(separator: ":").first ?? Substring(name)) : name
    }

    enum CodingKeys: String, CodingKey {
        case name, model, size, digest
        case modifiedAt = "modified_at"
    }
}

// MARK: - Pull Progress (streaming NDJSON from POST /api/pull)

struct PullProgress: Codable {
    let status: String
    let digest: String?
    let total: Int64?
    let completed: Int64?
}

// MARK: - Download State

enum DownloadState: Equatable {
    case idle
    case pulling(progress: Double, status: String)
    case complete
    case failed(String)
}
