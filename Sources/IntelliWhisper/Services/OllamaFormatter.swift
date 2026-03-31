import Foundation
import SwiftyBeaver

/// Formats transcriptions via a local Ollama instance using streaming chat completions.
struct OllamaFormatter: Formatting {
    private let baseURL: URL
    private let session: URLSession

    /// Reads the current model from UserDefaults so preference changes take effect immediately.
    private var model: String {
        UserDefaults.standard.string(forKey: SettingsService.Keys.ollamaModel) ?? SettingsService.defaultOllamaModel
    }

    private var generalSystemPrompt: String {
        let stored = UserDefaults.standard.string(forKey: SettingsService.Keys.generalSystemPrompt)
        if let stored, !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored
        }
        return SettingsService.defaultGeneralSystemPrompt
    }

    private var emailSystemPrompt: String {
        let stored = UserDefaults.standard.string(forKey: SettingsService.Keys.emailSystemPrompt)
        if let stored, !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored
        }
        return SettingsService.defaultEmailSystemPrompt
    }

    private func systemPrompt(for context: FormatContext) -> String {
        switch context {
        case .general: return generalSystemPrompt
        case .email: return emailSystemPrompt
        }
    }

    init(baseURL: URL = URL(string: "http://localhost:11434")!) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    // MARK: - Formatting

    /// Stream-formatted text from Ollama, yielding one token at a time.
    /// The pipeline collects tokens for the final clipboard copy and
    /// the UI can display them progressively as they arrive.
    func format(
        transcription: String,
        context: FormatContext,
        language: Language
    ) -> AsyncThrowingStream<String, Error> {
        let currentModel = model
        log.info("Using model: \(currentModel)")
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildRequest(
                        transcription: transcription,
                        context: context,
                        language: language
                    )

                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        log.error("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1) from Ollama")
                        throw OllamaError.requestFailed
                    }

                    // Ollama streams newline-delimited JSON objects, one per token.
                    for try await line in bytes.lines {
                        guard let data = line.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(ChatChunk.self, from: data),
                              let token = chunk.message?.content,
                              !token.isEmpty else {
                            continue
                        }
                        continuation.yield(token)

                        if chunk.done == true {
                            break
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            // Cancel the HTTP request if the consumer stops reading.
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Warmup

    /// Send a minimal request to preload the model into VRAM.
    func warmup() async {
        let url = baseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body = ChatRequest(
            model: model,
            messages: [.init(role: "user", content: "Hi")],
            stream: false,
            think: false,
            keep_alive: -1,
            options: .init(temperature: 0.1, num_ctx: nil)
        )
        request.httpBody = try? JSONEncoder().encode(body)

        _ = try? await session.data(for: request)
        log.info("Model warmup complete")
    }

    // MARK: - Health Check

    /// Verify Ollama is reachable and the configured model is pulled.
    /// Called on launch and periodically; drives the yellow warning icon.
    func healthCheck() async -> Bool {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        guard let (data, response) = try? await session.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            log.warning("Health check failed — Ollama unreachable")
            return false
        }

        guard let json = try? JSONDecoder().decode(TagsResponse.self, from: data) else {
            log.warning("Health check failed — invalid response")
            return false
        }

        let found = json.models.contains { $0.name.hasPrefix(model) }
        if found {
            log.info("Health check OK — model \(model) available")
        } else {
            log.warning("Health check: Ollama reachable but model \(model) not found")
        }
        return found
    }

    /// Check whether Ollama is reachable (ignoring model availability).
    func isReachable() async -> Bool {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        guard let (_, response) = try? await session.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return false
        }
        return true
    }

    // MARK: - Model Pull

    /// Pull a model from Ollama, streaming progress updates.
    func pullModel(name: String) -> AsyncThrowingStream<PullProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = baseURL.appendingPathComponent("api/pull")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(PullRequest(name: name))

                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        throw OllamaError.requestFailed
                    }

                    for try await line in bytes.lines {
                        guard let data = line.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(PullChunk.self, from: data) else {
                            continue
                        }

                        continuation.yield(PullProgress(
                            status: chunk.status,
                            completed: chunk.completed,
                            total: chunk.total
                        ))

                        if chunk.status == "success" {
                            break
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Model listing

    /// Fetch all model names from the Ollama backend.
    func fetchModels() async -> [String] {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        guard let (data, response) = try? await session.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let json = try? JSONDecoder().decode(TagsResponse.self, from: data) else {
            log.warning("Failed to fetch model list")
            return []
        }

        let models = json.models.map(\.name).sorted()
        log.info("Fetched \(models.count) model(s): \(models)")
        return models
    }

    // MARK: - Request building

    private func buildRequest(
        transcription: String,
        context: FormatContext,
        language: Language
    ) throws -> URLRequest {
        let url = baseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let userMessage = """
            Language: \(language.rawValue)

            \(transcription)
            """

        let body = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt(for: context)),
                .init(role: "user", content: userMessage),
            ],
            stream: true,
            think: false,
            keep_alive: -1,
            options: .init(temperature: 0.1, num_ctx: 4096)
        )

        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}

// MARK: - JSON models

private struct ChatRequest: Encodable {
    let model: String
    let messages: [Message]
    let stream: Bool
    let think: Bool
    let keep_alive: Int
    let options: Options

    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct Options: Encodable {
        let temperature: Double
        let num_ctx: Int?
    }
}

private struct ChatChunk: Decodable {
    let message: ChunkMessage?
    let done: Bool?

    struct ChunkMessage: Decodable {
        let content: String?
    }
}

private struct PullRequest: Encodable {
    let name: String
}

private struct PullChunk: Decodable {
    let status: String
    let completed: Int64?
    let total: Int64?
}

private struct TagsResponse: Decodable {
    let models: [ModelEntry]

    struct ModelEntry: Decodable {
        let name: String
    }
}

enum OllamaError: Error, LocalizedError {
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "Ollama request failed."
        }
    }
}