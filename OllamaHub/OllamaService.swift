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

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .parseError: return "Failed to parse response"
        case .pullFailed(let msg): return "Pull failed: \(msg)"
        case .deleteFailed(let name): return "Failed to delete \(name)"
        }
    }
}
