import Foundation

enum LocalContentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case selection
    case article
    case wikipedia
    case youtube

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .selection: return "Text"
        case .article: return "Article"
        case .wikipedia: return "Wikipedia"
        case .youtube: return "YouTube"
        }
    }

    var icon: String {
        switch self {
        case .selection: return "text.quote"
        case .article: return "doc.text"
        case .wikipedia: return "book.closed"
        case .youtube: return "play.rectangle"
        }
    }
}

struct ExtractedContent: Equatable, Sendable {
    let kind: LocalContentKind
    let title: String
    let sourceURL: URL
    let text: String?
    let author: String?
    let thumbnailURL: URL?
}

enum ContentExtractionError: Error, LocalizedError, Equatable {
    case invalidURL
    case unsupportedURL
    case invalidResponse
    case pageTooLarge
    case noReadableContent
    case captionsUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Copy a complete web address first."
        case .unsupportedURL: return "Only web pages using HTTP or HTTPS are supported."
        case .invalidResponse: return "The page returned an unreadable response."
        case .pageTooLarge: return "The page was too large to process safely."
        case .noReadableContent: return "Vibe Read could not find readable text on this page."
        case .captionsUnavailable: return "This YouTube video has no public captions to read. You can still save the link."
        }
    }
}

struct ContentExtractionService: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    static let maximumPageBytes = 4_000_000
    private let transport: Transport

    init(transport: @escaping Transport = { request in
        try await Self.ephemeralTransport(request)
    }) {
        self.transport = transport
    }

    static func normalizedWebURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.user == nil,
              components.password == nil,
              components.host?.isEmpty == false else { return nil }
        components.fragment = nil
        return components.url
    }

    static func kind(for url: URL) -> LocalContentKind {
        let host = normalizedHost(url)
        if host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com") {
            return .youtube
        }
        if host == "wikipedia.org" || host.hasSuffix(".wikipedia.org") {
            return .wikipedia
        }
        return .article
    }

    func extract(_ url: URL) async throws -> ExtractedContent {
        guard Self.normalizedWebURL(from: url.absoluteString) != nil else {
            throw ContentExtractionError.unsupportedURL
        }
        if Self.kind(for: url) == .youtube {
            return try await extractYouTube(url)
        }
        return try await extractHTMLPage(url)
    }

    func extractYouTube(_ url: URL) async throws -> ExtractedContent {
        guard let videoID = Self.youtubeVideoID(from: url) else {
            throw ContentExtractionError.invalidURL
        }
        let canonical = URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
        async let metadata = youtubeMetadata(canonical)
        async let captions = youtubeCaptions(canonical)
        let resolvedMetadata = try? await metadata
        let resolvedCaptions = try? await captions
        return ExtractedContent(
            kind: .youtube,
            title: resolvedMetadata?.title ?? "YouTube video",
            sourceURL: canonical,
            text: resolvedCaptions,
            author: resolvedMetadata?.author,
            thumbnailURL: resolvedMetadata?.thumbnail
        )
    }

    private func extractHTMLPage(_ url: URL) async throws -> ExtractedContent {
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 VibeRead/1.0",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport(request)
        guard (200..<300).contains(response.statusCode) else {
            throw ContentExtractionError.invalidResponse
        }
        guard data.count <= Self.maximumPageBytes else { throw ContentExtractionError.pageTooLarge }
        guard let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw ContentExtractionError.invalidResponse
        }
        let title = Self.firstMatch(
            in: html,
            patterns: [
                #"<meta[^>]+property=[\"']og:title[\"'][^>]+content=[\"']([^\"']+)[\"']"#,
                #"<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+property=[\"']og:title[\"']"#,
                #"<title[^>]*>(.*?)</title>"#
            ]
        ).map(Self.decodeHTMLEntities) ?? url.host ?? "Saved page"
        let articleHTML = Self.firstMatch(
            in: html,
            patterns: [#"<article\b[^>]*>([\s\S]*?)</article>"#, #"<main\b[^>]*>([\s\S]*?)</main>"#]
        ) ?? html
        let text = Self.readableText(from: articleHTML)
        guard text.count >= 80 else { throw ContentExtractionError.noReadableContent }
        return ExtractedContent(
            kind: Self.kind(for: url),
            title: title,
            sourceURL: url,
            text: text,
            author: nil,
            thumbnailURL: nil
        )
    }

    private struct YouTubeMetadata: Sendable {
        let title: String
        let author: String?
        let thumbnail: URL?
    }

    private func youtubeMetadata(_ canonicalURL: URL) async throws -> YouTubeMetadata {
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [
            URLQueryItem(name: "url", value: canonicalURL.absoluteString),
            URLQueryItem(name: "format", value: "json")
        ]
        let (data, response) = try await transport(URLRequest(url: components.url!))
        guard (200..<300).contains(response.statusCode) else {
            throw ContentExtractionError.invalidResponse
        }
        struct Response: Decodable {
            let title: String
            let authorName: String?
            let thumbnailURL: URL?
            enum CodingKeys: String, CodingKey {
                case title
                case authorName = "author_name"
                case thumbnailURL = "thumbnail_url"
            }
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return .init(title: decoded.title, author: decoded.authorName, thumbnail: decoded.thumbnailURL)
    }

    private func youtubeCaptions(_ canonicalURL: URL) async throws -> String {
        var request = URLRequest(url: canonicalURL, timeoutInterval: 25)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        let (pageData, response) = try await transport(request)
        guard (200..<300).contains(response.statusCode),
              pageData.count <= Self.maximumPageBytes,
              let page = String(data: pageData, encoding: .utf8),
              let tracksJSON = Self.jsonArray(after: #""captionTracks":"#, in: page),
              let tracksData = tracksJSON.data(using: .utf8) else {
            throw ContentExtractionError.captionsUnavailable
        }
        struct Track: Decodable {
            let baseURL: String
            let languageCode: String?
            enum CodingKeys: String, CodingKey {
                case baseURL = "baseUrl"
                case languageCode
            }
        }
        let tracks = try JSONDecoder().decode([Track].self, from: tracksData)
        guard let selected = tracks.first(where: { $0.languageCode?.hasPrefix("en") == true })
                ?? tracks.first,
              var components = URLComponents(string: selected.baseURL) else {
            throw ContentExtractionError.captionsUnavailable
        }
        var query = components.queryItems ?? []
        query.removeAll { $0.name == "fmt" }
        query.append(URLQueryItem(name: "fmt", value: "json3"))
        components.queryItems = query
        guard let captionsURL = components.url else { throw ContentExtractionError.captionsUnavailable }
        let (captionData, captionResponse) = try await transport(URLRequest(url: captionsURL))
        guard (200..<300).contains(captionResponse.statusCode) else {
            throw ContentExtractionError.captionsUnavailable
        }
        struct CaptionResponse: Decodable {
            struct Event: Decodable {
                struct Segment: Decodable { let utf8: String? }
                let segs: [Segment]?
            }
            let events: [Event]
        }
        let decoded = try JSONDecoder().decode(CaptionResponse.self, from: captionData)
        let text = decoded.events.compactMap { event in
            event.segs?.compactMap(\.utf8).joined()
        }
        .joined(separator: " ")
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ContentExtractionError.captionsUnavailable }
        return text
    }

    static func youtubeVideoID(from url: URL) -> String? {
        let host = normalizedHost(url)
        if host == "youtu.be" {
            return validYouTubeID(url.path.split(separator: "/").first.map(String.init))
        }
        if host == "youtube.com" || host.hasSuffix(".youtube.com") {
            if url.path == "/watch" {
                return validYouTubeID(
                    URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "v" })?.value
                )
            }
            let pieces = url.path.split(separator: "/")
            if pieces.count >= 2 && ["shorts", "embed", "live"].contains(String(pieces[0])) {
                return validYouTubeID(String(pieces[1]))
            }
        }
        return nil
    }

    private static func validYouTubeID(_ value: String?) -> String? {
        guard let value,
              value.range(of: #"^[A-Za-z0-9_-]{6,20}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return value
    }

    private static func normalizedHost(_ url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func firstMatch(in value: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else { continue }
            let range = NSRange(value.startIndex..., in: value)
            guard let match = regex.firstMatch(in: value, range: range),
                  match.numberOfRanges > 1,
                  let swiftRange = Range(match.range(at: 1), in: value) else { continue }
            return String(value[swiftRange])
        }
        return nil
    }

    private static func readableText(from html: String) -> String {
        var value = html
        let removals = ["script", "style", "svg", "noscript", "nav", "footer", "form"]
        for tag in removals {
            value = value.replacingOccurrences(
                of: "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)>",
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        value = value.replacingOccurrences(
            of: #"<(br|/p|/div|/li|/h[1-6]|/section|/article|/blockquote)\b[^>]*>"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        value = value.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        value = decodeHTMLEntities(value)
        value = value.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"\n\s*\n\s*\n+"#, with: "\n\n", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        var result = value
        let entities = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&hellip;": "…",
            "&mdash;": "—", "&ndash;": "–"
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        let regex = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#)
        let matches = regex?.matches(
            in: result,
            range: NSRange(result.startIndex..., in: result)
        ).reversed() ?? []
        for match in matches {
            guard let range = Range(match.range(at: 0), in: result),
                  let numberRange = Range(match.range(at: 1), in: result) else { continue }
            let encoded = String(result[numberRange])
            let value = encoded.hasPrefix("x")
                ? UInt32(encoded.dropFirst(), radix: 16)
                : UInt32(encoded, radix: 10)
            if let value, let scalar = UnicodeScalar(value) {
                result.replaceSubrange(range, with: String(scalar))
            }
        }
        return result
    }

    private static func jsonArray(after marker: String, in value: String) -> String? {
        guard let markerRange = value.range(of: marker),
              let start = value[markerRange.upperBound...].firstIndex(of: "[") else { return nil }
        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var index = start
        while index < value.endIndex {
            let character = value[index]
            if isInsideString {
                if isEscaped { isEscaped = false }
                else if character == "\\" { isEscaped = true }
                else if character == "\"" { isInsideString = false }
            } else if character == "\"" {
                isInsideString = true
            } else if character == "[" {
                depth += 1
            } else if character == "]" {
                depth -= 1
                if depth == 0 { return String(value[start...index]) }
            }
            index = value.index(after: index)
        }
        return nil
    }

    private static func ephemeralTransport(
        _ request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForResource = 45
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ContentExtractionError.invalidResponse
        }
        return (data, http)
    }
}
