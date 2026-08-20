import Foundation

struct ElevenLabsVoice: Codable, Identifiable, Equatable, Sendable {
    let voiceID: String
    let name: String
    let category: String?
    let description: String?
    let previewURL: URL?
    let labels: [String: String]

    var id: String { voiceID }

    private enum CodingKeys: String, CodingKey {
        case voiceID = "voice_id"
        case name
        case category
        case description
        case previewURL = "preview_url"
        case labels
    }

    init(
        voiceID: String,
        name: String,
        category: String? = nil,
        description: String? = nil,
        previewURL: URL? = nil,
        labels: [String: String] = [:]
    ) {
        self.voiceID = voiceID
        self.name = name
        self.category = category
        self.description = description
        self.previewURL = previewURL
        self.labels = labels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        voiceID = try container.decode(String.self, forKey: .voiceID)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        previewURL = try container.decodeIfPresent(URL.self, forKey: .previewURL)
        labels = try container.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
    }

    var detail: String {
        let values = [
            labels["accent"],
            labels["gender"],
            labels["age"],
            labels["use_case"]
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? (description ?? category ?? "ElevenLabs voice") : values.joined(separator: " · ")
    }

    func matches(searchTerm: String) -> Bool {
        let query = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let searchableValues = [name, category, description]
            .compactMap { $0 }
            + labels.flatMap { [$0.key, $0.value] }
        return searchableValues.contains {
            $0.localizedCaseInsensitiveContains(query)
        }
    }
}

struct ElevenLabsVoiceSettings: Codable, Equatable, Sendable {
    let stability: Double
    let similarityBoost: Double
    let style: Double
    let useSpeakerBoost: Bool
    let speed: Double

    private enum CodingKeys: String, CodingKey {
        case stability
        case similarityBoost = "similarity_boost"
        case style
        case useSpeakerBoost = "use_speaker_boost"
        case speed
    }
}

enum ElevenLabsTTSError: Error, LocalizedError, Equatable {
    case emptyText
    case invalidVoice
    case invalidResponse
    case rejectedCredential
    case provider(Int, String)
    case responseTooLarge

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "Enter a short preview phrase first."
        case .invalidVoice:
            return "Choose an ElevenLabs voice first."
        case .invalidResponse:
            return "ElevenLabs returned an unreadable response."
        case .rejectedCredential:
            return "ElevenLabs rejected the saved API key. Open Settings and save it again."
        case .provider(_, let message):
            return message
        case .responseTooLarge:
            return "The generated audio was too large to play safely."
        }
    }
}

struct ElevenLabsTTSClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    static let voicesURL = URL(string: "https://api.elevenlabs.io/v2/voices?page_size=100&include_total_count=false&sort=name&sort_direction=asc")!
    static let maximumAudioBytes = 50_000_000
    private static let maximumVoicePages = 25

    private let transport: Transport

    init(transport: @escaping Transport = { request in
        try await Self.ephemeralTransport(request)
    }) {
        self.transport = transport
    }

    func listVoices(apiKey: String) async throws -> [ElevenLabsVoice] {
        struct Envelope: Decodable {
            let voices: [ElevenLabsVoice]
            let hasMore: Bool?
            let nextPageToken: String?

            enum CodingKeys: String, CodingKey {
                case voices
                case hasMore = "has_more"
                case nextPageToken = "next_page_token"
            }
        }

        var voices: [ElevenLabsVoice] = []
        var seenVoiceIDs = Set<String>()
        var seenPageTokens = Set<String>()
        var nextPageToken: String?

        for _ in 0..<Self.maximumVoicePages {
            try Task.checkCancellation()
            let url = try Self.voiceListURL(nextPageToken: nextPageToken)
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.httpMethod = "GET"
            request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
            let (data, response) = try await transport(request)
            try Self.validate(response: response, data: data)
            guard let decoded = try? JSONDecoder().decode(Envelope.self, from: data) else {
                throw ElevenLabsTTSError.invalidResponse
            }
            for voice in decoded.voices where seenVoiceIDs.insert(voice.voiceID).inserted {
                voices.append(voice)
            }
            guard decoded.hasMore == true,
                  let token = decoded.nextPageToken?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  ),
                  !token.isEmpty,
                  seenPageTokens.insert(token).inserted else {
                break
            }
            nextPageToken = token
        }

        return voices.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func synthesize(
        text: String,
        voiceID: String,
        modelID: String,
        settings: ElevenLabsVoiceSettings,
        apiKey: String
    ) async throws -> Data {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { throw ElevenLabsTTSError.emptyText }
        let trimmedVoice = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedVoice.isEmpty,
              let encodedVoice = trimmedVoice.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
              ),
              let url = URL(
                string: "https://api.elevenlabs.io/v1/text-to-speech/\(encodedVoice)?output_format=mp3_44100_128"
              ) else {
            throw ElevenLabsTTSError.invalidVoice
        }
        struct Payload: Encodable {
            let text: String
            let modelID: String
            let voiceSettings: ElevenLabsVoiceSettings

            enum CodingKeys: String, CodingKey {
                case text
                case modelID = "model_id"
                case voiceSettings = "voice_settings"
            }
        }
        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(
            Payload(text: trimmedText, modelID: modelID, voiceSettings: settings)
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let (data, response) = try await transport(request)
        try Self.validate(response: response, data: data)
        guard !data.isEmpty else { throw ElevenLabsTTSError.invalidResponse }
        guard data.count <= Self.maximumAudioBytes else {
            throw ElevenLabsTTSError.responseTooLarge
        }
        return data
    }

    private static func validate(response: HTTPURLResponse, data: Data) throws {
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw ElevenLabsTTSError.rejectedCredential
            }
            let safeMessage = providerMessage(from: data)
            throw ElevenLabsTTSError.provider(
                response.statusCode,
                safeMessage?.isEmpty == false
                    ? safeMessage!
                    : "ElevenLabs could not generate speech."
            )
        }
    }

    private static func voiceListURL(nextPageToken: String?) throws -> URL {
        guard var components = URLComponents(url: voicesURL, resolvingAgainstBaseURL: false) else {
            throw ElevenLabsTTSError.invalidResponse
        }
        if let nextPageToken {
            components.queryItems?.append(
                URLQueryItem(name: "next_page_token", value: nextPageToken)
            )
        }
        guard let url = components.url else { throw ElevenLabsTTSError.invalidResponse }
        return url
    }

    private static func providerMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let envelope = object as? [String: Any] else { return nil }
        let rawMessage: String?
        if let detail = envelope["detail"] as? String {
            rawMessage = detail
        } else if let detail = envelope["detail"] as? [String: Any] {
            rawMessage = detail["message"] as? String
                ?? detail["status"] as? String
        } else {
            rawMessage = envelope["message"] as? String
        }
        let trimmed = rawMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func ephemeralTransport(
        _ request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForResource = 120
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ElevenLabsTTSError.invalidResponse
        }
        return (data, http)
    }
}
