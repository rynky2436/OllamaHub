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
    case chat = "Chat"
    case bench = "Bench"
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

// MARK: - Model Tags (from ollama.com/library/MODEL/tags)

struct ModelTag: Identifiable, Hashable {
    let name: String      // e.g. "gemma3:27b-it-q4_0"
    let tag: String       // e.g. "27b-it-q4_0"
    let size: String      // e.g. "17GB"
    var id: String { name }
}

// MARK: - Model Info (from POST /api/show)

struct ModelInfo: Codable {
    let license: String?
    let modelfile: String?
    let parameters: String?
    let template: String?
    let details: ModelInfoDetails?
    let capabilities: [String]?
    let modifiedAt: String?

    enum CodingKeys: String, CodingKey {
        case license, modelfile, parameters, template, details, capabilities
        case modifiedAt = "modified_at"
    }
}

struct ModelInfoDetails: Codable {
    let parentModel: String?
    let format: String?
    let family: String?
    let families: [String]?
    let parameterSize: String?
    let quantizationLevel: String?

    enum CodingKeys: String, CodingKey {
        case format, family, families
        case parentModel = "parent_model"
        case parameterSize = "parameter_size"
        case quantizationLevel = "quantization_level"
    }
}

// MARK: - Chat

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: String   // "user" or "assistant"
    var content: String
}

struct ChatResponseLine: Codable {
    let model: String?
    let message: ChatResponseMessage?
    let done: Bool
    let totalDuration: Int64?
    let loadDuration: Int64?
    let promptEvalCount: Int?
    let promptEvalDuration: Int64?
    let evalCount: Int?
    let evalDuration: Int64?

    enum CodingKeys: String, CodingKey {
        case model, message, done
        case totalDuration = "total_duration"
        case loadDuration = "load_duration"
        case promptEvalCount = "prompt_eval_count"
        case promptEvalDuration = "prompt_eval_duration"
        case evalCount = "eval_count"
        case evalDuration = "eval_duration"
    }
}

struct ChatResponseMessage: Codable {
    let role: String?
    let content: String?
}

// MARK: - Running Models (from GET /api/ps)

struct RunningModelsResponse: Codable {
    let models: [RunningModel]
}

struct RunningModel: Codable, Identifiable {
    let name: String
    let model: String
    let sizeVram: Int64
    let expiresAt: String
    let details: ModelInfoDetails?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, model, details
        case sizeVram = "size_vram"
        case expiresAt = "expires_at"
    }
}

// MARK: - Benchmark

struct BenchmarkResult: Identifiable {
    let id = UUID()
    let modelName: String
    let output: String
    let totalDuration: Double    // seconds
    let loadDuration: Double     // seconds
    let promptEvalCount: Int     // prompt tokens
    let promptEvalDuration: Double // seconds
    let evalCount: Int           // generated tokens
    let evalDuration: Double     // seconds
    let vramBytes: Int64         // VRAM used

    var tokensPerSecond: Double {
        evalDuration > 0 ? Double(evalCount) / evalDuration : 0
    }
    var timeToFirstToken: Double {
        promptEvalDuration + loadDuration
    }
    var promptTokensPerSecond: Double {
        promptEvalDuration > 0 ? Double(promptEvalCount) / promptEvalDuration : 0
    }
}
