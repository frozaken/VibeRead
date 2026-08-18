import Foundation

struct DictationResult: Codable, Equatable, Sendable {
    let rawTranscript: String
    let polishedText: String
    let durationMs: Int?
}

/// A narrow client for the OpenAI-compatible endpoint chosen by the user.
/// There are deliberately no Vibe Read server, auth, sync, storage, billing,
/// analytics, content, or profile endpoints in this type.
actor APIService {
    static let shared = APIService()

    enum APIError: Error, LocalizedError {
        case network(Error)
        case invalidResponse
        case unauthorized
        case server(Int)
        case invalidPayload(Error)
        case missingAPIKey
        case invalidConfiguration
        case provider(String)

        var errorDescription: String? {
            switch self {
            case .network(let error): return "Network error: \(error.localizedDescription)"
            case .invalidResponse: return "The provider returned an invalid response"
            case .unauthorized: return "The configured API key was rejected"
            case .server(let status): return "The provider returned HTTP \(status)"
            case .invalidPayload(let error): return "Could not read the provider response: \(error.localizedDescription)"
            case .missingAPIKey: return "Add your API key in Settings → AI Provider"
            case .invalidConfiguration: return "Check the provider URL and model names in Settings"
            case .provider(let message): return message
            }
        }
    }

    private init() {}

    func transcribeDictation(
        audioURL: URL,
        vocabulary: [String] = [],
        transformPrompt: String? = nil,
        clientId: String? = nil
    ) async throws -> DictationResult {
        _ = clientId // Kept for compatibility with migrated local history.
        let configuration = try await providerConfiguration()
        let endpoint = configuration.baseURL.appendingPathComponent("audio/transcriptions")
        let audio = try Data(contentsOf: audioURL)
        let fileExtension = audioURL.pathExtension.isEmpty ? "m4a" : audioURL.pathExtension.lowercased()
        let contentType = Self.audioContentType(for: fileExtension)
        let boundary = UUID().uuidString
        var body = Data()

        func appendField(name: String, value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data(value.utf8))
            body.append(Data("\r\n".utf8))
        }

        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"dictation.\(fileExtension)\"\r\n".utf8))
        body.append(Data("Content-Type: \(contentType)\r\n\r\n".utf8))
        body.append(audio)
        body.append(Data("\r\n".utf8))
        appendField(name: "model", value: configuration.transcriptionModel)
        appendField(name: "response_format", value: "json")

        let vocabularyPrompt = String(vocabulary.joined(separator: ", ").prefix(800))
        if !vocabularyPrompt.isEmpty {
            appendField(name: "prompt", value: vocabularyPrompt)
        }
        body.append(Data("--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        addAuthorization(configuration.apiKey, to: &request)

        let data = try await send(request)
        let response: TranscriptionResponse
        do {
            response = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        } catch {
            throw APIError.invalidPayload(error)
        }

        let raw = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { throw APIError.provider("The provider returned no transcript") }
        let polished: String
        if let transformPrompt,
           !transformPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            polished = try await transformText(raw, systemPrompt: transformPrompt)
        } else {
            polished = raw
        }
        return DictationResult(rawTranscript: raw, polishedText: polished, durationMs: nil)
    }

    func transformText(_ text: String, systemPrompt: String) async throws -> String {
        let configuration = try await providerConfiguration()
        let payload = ChatRequest(
            model: configuration.textModel,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: text)
            ],
            temperature: 0.2
        )
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthorization(configuration.apiKey, to: &request)

        let data = try await send(request)
        let response: ChatResponse
        do {
            response = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw APIError.invalidPayload(error)
        }
        guard let output = response.choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty else {
            throw APIError.provider("The text model returned no text")
        }
        return output
    }

    func testProviderConnection() async throws {
        let configuration = try await providerConfiguration()
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("models"))
        addAuthorization(configuration.apiKey, to: &request)
        _ = try await send(request)
    }

    private func providerConfiguration() async throws -> AIProviderConfiguration {
        guard let configuration = await MainActor.run(body: {
            AIProviderSettings.shared.configuration
        }) else {
            throw APIError.invalidConfiguration
        }
        guard !configuration.transcriptionModel.isEmpty, !configuration.textModel.isEmpty else {
            throw APIError.invalidConfiguration
        }
        if configuration.apiKey.isEmpty && !configuration.baseURL.isLoopbackProvider {
            throw APIError.missingAPIKey
        }
        return configuration
    }

    private func addAuthorization(_ apiKey: String, to request: inout URLRequest) {
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw APIError.unauthorized }
        guard (200...299).contains(http.statusCode) else {
            if let error = try? JSONDecoder().decode(ProviderErrorEnvelope.self, from: data),
               !error.error.message.isEmpty {
                throw APIError.provider(error.error.message)
            }
            throw APIError.server(http.statusCode)
        }
        return data
    }

    private static func audioContentType(for fileExtension: String) -> String {
        switch fileExtension {
        case "wav": return "audio/wav"
        case "mp3": return "audio/mpeg"
        case "webm": return "audio/webm"
        case "mp4": return "audio/mp4"
        default: return "audio/mp4"
        }
    }
}

private struct TranscriptionResponse: Decodable, Sendable {
    let text: String
}

private struct ChatRequest: Encodable, Sendable {
    struct Message: Codable, Sendable {
        let role: String
        let content: String
    }
    let model: String
    let messages: [Message]
    let temperature: Double
}

private struct ChatResponse: Decodable, Sendable {
    struct Choice: Decodable, Sendable {
        let message: ChatRequest.Message
    }
    let choices: [Choice]
}

private struct ProviderErrorEnvelope: Decodable, Sendable {
    struct ProviderError: Decodable, Sendable { let message: String }
    let error: ProviderError
}

private extension URL {
    var isLoopbackProvider: Bool {
        guard scheme == "http" else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }
}
