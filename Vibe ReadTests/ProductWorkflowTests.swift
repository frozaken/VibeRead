import Foundation
import Testing
@testable import Vibe_Read

struct ProductWorkflowTests {
    @Test func elevenLabsTTSUsesDirectCurrentContract() async throws {
        let capture = ProductRequestCapture()
        let client = ElevenLabsTTSClient { request in
            await capture.record(request)
            return (
                Data("synthetic-mp3".utf8),
                try productResponse(for: request, status: 200, contentType: "audio/mpeg")
            )
        }
        let settings = ElevenLabsVoiceSettings(
            stability: 0.4,
            similarityBoost: 0.8,
            style: 0.2,
            useSpeakerBoost: true,
            speed: 1.1
        )
        let output = try await client.synthesize(
            text: "Read this",
            voiceID: "voice-123",
            modelID: "eleven_multilingual_v2",
            settings: settings,
            apiKey: "synthetic-secret"
        )
        #expect(output == Data("synthetic-mp3".utf8))
        let capturedRequest = await capture.lastRequest
        let request = try #require(capturedRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/text-to-speech/voice-123")
        #expect(request.url?.query == "output_format=mp3_44100_128")
        #expect(request.value(forHTTPHeaderField: "xi-api-key") == "synthetic-secret")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["text"] as? String == "Read this")
        #expect(json["model_id"] as? String == "eleven_multilingual_v2")
        let voice = try #require(json["voice_settings"] as? [String: Any])
        #expect(voice["stability"] as? Double == 0.4)
        #expect(voice["similarity_boost"] as? Double == 0.8)
        #expect(voice["use_speaker_boost"] as? Bool == true)
        #expect(!String(data: body, encoding: .utf8)!.contains("synthetic-secret"))
    }

    @Test func elevenLabsVoicesAreExplicitlyLoadedAndSorted() async throws {
        let capture = ProductRequestCapture()
        let client = ElevenLabsTTSClient { request in
            await capture.record(request)
            let data = Data(#"{"voices":[{"voice_id":"z","name":"Zoey","labels":{}},{"voice_id":"a","name":"Adam","labels":{"accent":"American"}}]}"#.utf8)
            return (data, try productResponse(for: request, status: 200))
        }
        let voices = try await client.listVoices(apiKey: "voice-key")
        #expect(voices.map(\.name) == ["Adam", "Zoey"])
        let capturedRequest = await capture.lastRequest
        let request = try #require(capturedRequest)
        #expect(request.url?.path == "/v2/voices")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "xi-api-key") == "voice-key")
    }

    @Test func longReadAloudTextSplitsAtHumanBoundaries() {
        let text = "First sentence. Second sentence is longer. Third sentence ends here."
        let chunks = InstantTTSService.splitIntoChunks(text, maximumCharacters: 28)
        #expect(chunks.count >= 2)
        #expect(chunks.allSatisfy { !$0.isEmpty && $0.count <= 28 })
        #expect(chunks.joined(separator: " ").contains("First sentence"))
        #expect(chunks.joined(separator: " ").contains("Third sentence"))
    }

    @Test func copiedURLsAreClassifiedWithoutBrowserAutomation() throws {
        let wiki = try #require(ContentExtractionService.normalizedWebURL(
            from: " https://en.wikipedia.org/wiki/Swift_(programming_language)#History "
        ))
        #expect(wiki.fragment == nil)
        #expect(ContentExtractionService.kind(for: wiki) == .wikipedia)

        let youtube = try #require(URL(string: "https://youtu.be/dQw4w9WgXcQ?t=4"))
        #expect(ContentExtractionService.kind(for: youtube) == .youtube)
        #expect(ContentExtractionService.youtubeVideoID(from: youtube) == "dQw4w9WgXcQ")
        #expect(ContentExtractionService.normalizedWebURL(from: "file:///etc/passwd") == nil)
        #expect(ContentExtractionService.normalizedWebURL(from: "not a URL") == nil)
    }

    @Test func articleExtractionRemovesPageChromeAndKeepsReadableText() async throws {
        let html = """
        <html><head><title>A useful page</title><style>bad css</style></head>
        <body><nav>Navigation noise</nav><article><h1>A useful page</h1>
        <p>This is the first useful paragraph with enough text to be extracted safely.</p>
        <p>This is a second useful paragraph that makes the article longer and readable.</p>
        <script>privateTracker()</script></article></body></html>
        """
        let service = ContentExtractionService { request in
            (Data(html.utf8), try productResponse(for: request, status: 200, contentType: "text/html"))
        }
        let url = try #require(URL(string: "https://example.com/article"))
        let extracted = try await service.extract(url)
        #expect(extracted.kind == .article)
        #expect(extracted.title == "A useful page")
        #expect(extracted.text?.contains("first useful paragraph") == true)
        #expect(extracted.text?.contains("Navigation noise") == false)
        #expect(extracted.text?.contains("privateTracker") == false)
    }

    @Test @MainActor func localLibraryPersistsWithoutAnAccountOrServer() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeReadLibraryTests-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("library.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = LocalLibraryStore(fileURL: file)
        let saved = try #require(store.saveText(
            "A local note worth keeping for later.",
            title: "Local note"
        ))
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(saved.kind == .selection)

        let reloaded = LocalLibraryStore(fileURL: file)
        #expect(reloaded.items.count == 1)
        #expect(reloaded.items.first?.title == "Local note")
        #expect(reloaded.items.first?.text == "A local note worth keeping for later.")
    }
}

private actor ProductRequestCapture {
    private(set) var lastRequest: URLRequest?
    func record(_ request: URLRequest) { lastRequest = request }
}

private func productResponse(
    for request: URLRequest,
    status: Int,
    contentType: String = "application/json"
) throws -> HTTPURLResponse {
    guard let url = request.url else { throw ProductTestFailure.missingURL }
    guard let response = HTTPURLResponse(
        url: url,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": contentType]
    ) else { throw ProductTestFailure.invalidResponse }
    return response
}

private enum ProductTestFailure: Error {
    case missingURL
    case invalidResponse
}
