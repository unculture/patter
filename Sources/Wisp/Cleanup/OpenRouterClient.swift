import Foundation

/// A model choice for the AI cleanup, as shown in the settings.
struct CleanupModel: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String

    /// Prices are from openrouter.ai/api/v1/models on 1 October 2026. One dictation of about
    /// 150 words uses about 900 input and 250 output tokens.
    static let presets = [
        CleanupModel(
            id: "openai/gpt-5.6-luna", title: "GPT-5.6 Luna",
            detail: "Fast and low cost. About $0.0005 per dictation."),
        CleanupModel(
            id: "anthropic/claude-haiku-4.5", title: "Claude Haiku 4.5",
            detail: "Careful with meaning and names. About $0.002 per dictation."),
        CleanupModel(
            id: "openai/gpt-oss-120b", title: "gpt-oss-120b",
            detail: "Open model on very fast servers. About $0.0001 per dictation."),
    ]
}

enum OpenRouterError: LocalizedError {
    case http(status: Int, message: String)
    case emptyResponse
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .http(let status, let message): "OpenRouter error \(status): \(message)"
        case .emptyResponse: "The model returned no text"
        case .invalidResponse: "OpenRouter sent a response that Wisp cannot read"
        }
    }
}

struct OpenRouterClient {
    /// WISP_OPENROUTER_URL replaces the server, for tests against a local mock.
    static let baseURL = URL(
        string: ProcessInfo.processInfo.environment["WISP_OPENROUTER_URL"] ?? "https://openrouter.ai/api/v1")!

    let apiKey: String
    var session: URLSession = .shared

    struct Usage {
        let promptTokens: Int
        let completionTokens: Int
    }

    func complete(
        model: String, system: String, user: String, maxTokens: Int, timeout: TimeInterval
    ) async throws -> (text: String, usage: Usage?) {
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "temperature": 0,
            "provider": ["sort": "latency"],
        ]
        var tokenLimit = maxTokens
        if let effort = await ReasoningCatalog.shared.lowestEffort(for: model) {
            body["reasoning"] = ["effort": effort, "exclude": true]
            // Reasoning tokens count against max_tokens.
            if effort != "none" { tokenLimit += 1024 }
        }
        body["max_tokens"] = tokenLimit

        var request = URLRequest(url: Self.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        authorize(&request)

        let (data, response) = try await session.data(for: request)
        try Self.check(response, data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any]
        else { throw OpenRouterError.invalidResponse }
        guard let content = message["content"] as? String, !content.isEmpty else {
            throw OpenRouterError.emptyResponse
        }
        var usage: Usage?
        if let raw = json["usage"] as? [String: Any] {
            usage = Usage(
                promptTokens: raw["prompt_tokens"] as? Int ?? 0,
                completionTokens: raw["completion_tokens"] as? Int ?? 0)
        }
        return (content, usage)
    }

    /// Checks the key without using credit. Returns the key's label and the credit it used so far.
    func checkKey() async throws -> (label: String?, usage: Double?) {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("key"))
        request.timeoutInterval = 10
        authorize(&request)
        let (data, response) = try await session.data(for: request)
        try Self.check(response, data)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let info = json?["data"] as? [String: Any]
        return (info?["label"] as? String, info?["usage"] as? Double)
    }

    private func authorize(_ request: inout URLRequest) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Wisp", forHTTPHeaderField: "X-OpenRouter-Title")
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw OpenRouterError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let error = json?["error"] as? [String: Any]
            let message = error?["message"] as? String
                ?? String(data: data, encoding: .utf8)?.prefix(200).description
                ?? "No details"
            throw OpenRouterError.http(status: http.statusCode, message: message)
        }
    }
}

/// Reads from the public model list which reasoning setting each model accepts, so that
/// Wisp asks for the least reasoning: the cleanup needs speed, not deep thought.
actor ReasoningCatalog {
    static let shared = ReasoningCatalog()

    private var models: [String: [String: Any]]?
    private var loading: Task<[String: [String: Any]], Never>?

    /// "none" when the model can switch reasoning off, else its lightest effort.
    /// nil when the model has no reasoning setting, or when the list is not available.
    func lowestEffort(for model: String) async -> String? {
        let catalog = await load()
        guard let reasoning = catalog[model]?["reasoning"] as? [String: Any], !reasoning.isEmpty else { return nil }
        let efforts = reasoning["supported_efforts"] as? [String] ?? []
        if efforts.isEmpty {
            // For example Claude Haiku: reasoning exists but is off unless requested.
            return nil
        }
        for effort in ["none", "minimal", "low", "medium"] where efforts.contains(effort) {
            return effort
        }
        return nil
    }

    private func load() async -> [String: [String: Any]] {
        if let models { return models }
        if let loading { return await loading.value }
        let task = Task<[String: [String: Any]], Never> {
            var request = URLRequest(url: OpenRouterClient.baseURL.appendingPathComponent("models"))
            request.timeoutInterval = 5
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["data"] as? [[String: Any]]
            else { return [:] }
            var byID: [String: [String: Any]] = [:]
            for entry in list {
                if let id = entry["id"] as? String { byID[id] = entry }
            }
            return byID
        }
        loading = task
        let result = await task.value
        loading = nil
        // Keep a failed (empty) result only for this call, so that the next call tries again.
        if !result.isEmpty { models = result }
        return result
    }

    /// Starts the download early, so that the first cleanup does not wait for it.
    func preload() async {
        _ = await load()
    }
}
