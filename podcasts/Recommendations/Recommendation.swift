import Foundation

/// One row in the Refold doc.
struct Recommendation: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let location: String?
    let mentions: Int
    let category: String?
    let region: String?
    let notes: String?
    let otherLinks: String?

    init(
        id: UUID = UUID(),
        title: String,
        location: String? = nil,
        mentions: Int = 0,
        category: String? = nil,
        region: String? = nil,
        notes: String? = nil,
        otherLinks: String? = nil
    ) {
        self.id = id
        self.title = title
        self.location = location
        self.mentions = mentions
        self.category = category
        self.region = region
        self.notes = notes
        self.otherLinks = otherLinks
    }

    /// Extracts the first `open.spotify.com/show/…` URL from `otherLinks`.
    var spotifyURL: URL? {
        guard let raw = otherLinks?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        return raw.components(separatedBy: CharacterSet(charactersIn: " ,\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { URL(string: $0) }
            .first { $0.host == "open.spotify.com" && $0.pathComponents.contains("show") }
    }

    /// Stable key for the match cache. Lowercased + whitespace-collapsed title.
    var matchKey: String {
        title.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// A section in the rendered list — derived from a "Level N - X Hours" divider row.
struct RecommendationSection: Identifiable, Codable, Equatable {
    let id: UUID
    let level: Int
    let title: String
    let hourThreshold: Int
    var recommendations: [Recommendation]

    init(
        id: UUID = UUID(),
        level: Int,
        title: String,
        hourThreshold: Int,
        recommendations: [Recommendation] = []
    ) {
        self.id = id
        self.level = level
        self.title = title
        self.hourThreshold = hourThreshold
        self.recommendations = recommendations
    }
}

/// Top-level snapshot stored on disk as recommendations_csv.json.
struct RecommendationsSnapshot: Codable, Equatable {
    let fetchedAt: Date
    let sections: [RecommendationSection]
}
