import Foundation

actor OllamaService {
    static let shared = OllamaService()

    private let localBase = "http://localhost:11434"
    private let libraryURL = "https://ollama.com/library?sort=newest"

    // MARK: - Check if Ollama is running

    func isRunning() async -> Bool {
        guard let url = URL(string: localBase) else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Fetch installed models from local Ollama

    func fetchInstalledModels() async throws -> [LocalModel] {
        guard let url = URL(string: "\(localBase)/api/tags") else {
            throw OllamaError.invalidURL
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(LocalModelsResponse.self, from: data)
        return response.models
    }

    // MARK: - Fetch model catalog from ollama.com/library (HTML scrape)

    func fetchLibraryModels() async throws -> [OllamaModel] {
        guard let url = URL(string: libraryURL) else {
            throw OllamaError.invalidURL
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw OllamaError.parseError
        }
        return parseLibraryHTML(html)
    }

    // MARK: - Pull a model with streaming progress

    func pullModel(
        name: String,
        onProgress: @escaping @Sendable (PullProgress) -> Void
    ) async throws {
        guard let url = URL(string: "\(localBase)/api/pull") else {
            throw OllamaError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{\"model\":\"\(name)\",\"stream\":true}".data(using: .utf8)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.pullFailed("No response")
        }
        guard httpResponse.statusCode == 200 else {
            // Try to read error body
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 500 { break }
            }
            throw OllamaError.pullFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        let decoder = JSONDecoder()
        for try await line in bytes.lines {
            guard let lineData = line.data(using: .utf8) else { continue }
            if let progress = try? decoder.decode(PullProgress.self, from: lineData) {
                onProgress(progress)
            }
        }
    }

    // MARK: - Benchmark a model (non-streaming, returns metrics)

    func benchmark(model: String, prompt: String) async throws -> BenchmarkResult {
        guard let url = URL(string: "\(localBase)/api/chat") else {
            throw OllamaError.invalidURL
        }

        let escaped = escapeJSON(prompt)
        let body = "{\"model\":\"\(model)\",\"messages\":[{\"role\":\"user\",\"content\":\"\(escaped)\"}],\"stream\":false}"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)
        request.timeoutInterval = 600 // 10 min for large models

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OllamaError.chatFailed("Benchmark request failed")
        }

        let decoded = try JSONDecoder().decode(ChatResponseLine.self, from: data)

        // Get VRAM usage
        var vram: Int64 = 0
        if let running = try? await listRunning() {
            vram = running.first(where: { $0.name == model })?.sizeVram ?? 0
        }

        return BenchmarkResult(
            modelName: model,
            output: decoded.message?.content ?? "",
            totalDuration: Double(decoded.totalDuration ?? 0) / 1_000_000_000,
            loadDuration: Double(decoded.loadDuration ?? 0) / 1_000_000_000,
            promptEvalCount: decoded.promptEvalCount ?? 0,
            promptEvalDuration: Double(decoded.promptEvalDuration ?? 0) / 1_000_000_000,
            evalCount: decoded.evalCount ?? 0,
            evalDuration: Double(decoded.evalDuration ?? 0) / 1_000_000_000,
            vramBytes: vram
        )
    }

    // MARK: - Delete a model

    func deleteModel(name: String) async throws {
        guard let url = URL(string: "\(localBase)/api/delete") else {
            throw OllamaError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{\"model\":\"\(name)\"}".data(using: .utf8)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OllamaError.deleteFailed(name)
        }
    }

    // MARK: - Fetch all tags for a model (scrape tags page)

    func fetchModelTags(name: String) async throws -> [ModelTag] {
        guard let url = URL(string: "https://ollama.com/library/\(name)/tags") else {
            throw OllamaError.invalidURL
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else {
            throw OllamaError.parseError
        }

        let tagLinks = matches(for: "href=\"/library/\(NSRegularExpression.escapedPattern(for: name)):([^\"]+)\"", in: html)
        let uniqueTags = tagLinks.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let allSizes = matches(for: #"(\d+(?:\.\d+)?\s*(?:GB|MB|KB|B))"#, in: html)
        // Sizes appear doubled in the HTML (mobile + desktop views)
        let sizes = stride(from: 0, to: allSizes.count, by: 2).map { allSizes[$0] }

        var result: [ModelTag] = []
        for (i, tag) in uniqueTags.enumerated() {
            result.append(ModelTag(
                name: "\(name):\(tag)",
                tag: tag,
                size: i < sizes.count ? sizes[i] : ""
            ))
        }
        return result
    }

    // MARK: - Show model info (local)

    func showModel(name: String) async throws -> ModelInfo {
        guard let url = URL(string: "\(localBase)/api/show") else {
            throw OllamaError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{\"name\":\"\(name)\"}".data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(ModelInfo.self, from: data)
    }

    // MARK: - Chat with streaming

    func chat(
        model: String,
        messages: [(role: String, content: String)],
        onToken: @escaping @Sendable (String) -> Void
    ) async throws {
        guard let url = URL(string: "\(localBase)/api/chat") else {
            throw OllamaError.invalidURL
        }

        let msgArray = messages.map { "{\"role\":\"\($0.role)\",\"content\":\"\(escapeJSON($0.content))\"}" }
        let body = "{\"model\":\"\(model)\",\"messages\":[\(msgArray.joined(separator: ","))],\"stream\":true}"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OllamaError.chatFailed("Server error")
        }

        let decoder = JSONDecoder()
        for try await line in bytes.lines {
            guard let lineData = line.data(using: .utf8),
                  let resp = try? decoder.decode(ChatResponseLine.self, from: lineData) else { continue }
            if let content = resp.message?.content, !content.isEmpty {
                onToken(content)
            }
            if resp.done { break }
        }
    }

    // MARK: - List running models

    func listRunning() async throws -> [RunningModel] {
        guard let url = URL(string: "\(localBase)/api/ps") else {
            throw OllamaError.invalidURL
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(RunningModelsResponse.self, from: data)
        return response.models
    }

    // MARK: - Helpers

    private func escapeJSON(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    // MARK: - HTML Parsing

    private func parseLibraryHTML(_ html: String) -> [OllamaModel] {
        let titles = matches(for: #"x-test-model-title title="([^"]+)""#, in: html)
        let descriptions = matches(for: #"<p class="max-w-lg[^"]*"[^>]*>\s*([^<]+)"#, in: html)
        let pullCounts = matches(for: #"<span x-test-pull-count>([^<]+)</span>"#, in: html)
        let updated = matches(for: #"x-test-updated>([^<]+)<"#, in: html)

        // Capabilities are sparse — not every model has one
        // We need positional matching, so parse per-model blocks
        let capabilities = parseCapabilities(html, modelCount: titles.count)

        // Sizes are grouped per model — parse per model block
        let sizeGroups = parseSizeGroups(html, modelCount: titles.count)

        var models: [OllamaModel] = []
        for i in 0..<titles.count {
            let name = titles[i]
            let model = OllamaModel(
                id: name,
                name: name,
                description: decodeHTMLEntities(i < descriptions.count ? descriptions[i].trimmingCharacters(in: .whitespacesAndNewlines) : ""),
                pullCount: i < pullCounts.count ? pullCounts[i] : "",
                updated: i < updated.count ? updated[i] : "",
                capability: i < capabilities.count ? capabilities[i] : nil,
                sizes: i < sizeGroups.count ? sizeGroups[i] : []
            )
            models.append(model)
        }
        return models
    }

    private func parseCapabilities(_ html: String, modelCount: Int) -> [String?] {
        // Split HTML by model blocks and check each for capability
        let modelBlocks = html.components(separatedBy: "x-test-model-title title=")
        var caps: [String?] = []
        for (i, block) in modelBlocks.enumerated() {
            guard i > 0 else { continue } // skip before first model
            if let match = firstMatch(for: #"x-test-capability[^>]*>\s*([^<]+)<"#, in: block) {
                caps.append(match.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                caps.append(nil)
            }
        }
        return caps
    }

    private func parseSizeGroups(_ html: String, modelCount: Int) -> [[String]] {
        let modelBlocks = html.components(separatedBy: "x-test-model-title title=")
        var groups: [[String]] = []
        for (i, block) in modelBlocks.enumerated() {
            guard i > 0 else { continue }
            // Get regular size tags (x-test-size attribute)
            var sizes = matches(for: #"x-test-size[^>]*>\s*([^<]+)<"#, in: block)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            // Check for cloud tag (cyan-styled span without x-test-size)
            let hasCloud = block.contains("bg-cyan-50") && block.contains(">cloud<")
            if hasCloud {
                sizes.insert("cloud", at: 0)
            }
            groups.append(sizes)
        }
        return groups
    }

    // MARK: - Regex Helpers

    private func matches(for pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[captureRange])
        }
    }

    private func firstMatch(for pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captureRange])
    }

    private func decodeHTMLEntities(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }
}

enum OllamaError: LocalizedError {
    case invalidURL
    case parseError
    case pullFailed(String)
    case deleteFailed(String)
    case chatFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .parseError: return "Failed to parse response"
        case .pullFailed(let msg): return "Pull failed: \(msg)"
        case .deleteFailed(let name): return "Failed to delete \(name)"
        case .chatFailed(let msg): return "Chat failed: \(msg)"
        }
    }
}
