import Foundation

actor SpotifyOEmbedClient {
    static let shared = SpotifyOEmbedClient()
    private var cache: [URL: URL] = [:]

    private struct OEmbedResponse: Decodable {
        let thumbnail_url: String
    }

    func thumbnailURL(for spotifyURL: URL) async -> URL? {
        if let cached = cache[spotifyURL] { return cached }

        var components = URLComponents(string: "https://open.spotify.com/oembed")!
        components.queryItems = [URLQueryItem(name: "url", value: spotifyURL.absoluteString)]
        guard let oembedURL = components.url,
              let (data, _) = try? await URLSession.shared.data(from: oembedURL),
              let response = try? JSONDecoder().decode(OEmbedResponse.self, from: data),
              let thumbnailURL = URL(string: response.thumbnail_url)
        else { return nil }

        cache[spotifyURL] = thumbnailURL
        return thumbnailURL
    }
}
