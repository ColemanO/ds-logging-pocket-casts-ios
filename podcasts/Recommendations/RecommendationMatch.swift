import Foundation

/// Persisted match state for a Recommendation. Stored in
/// `recommendations_matches.json` keyed by `Recommendation.matchKey`.
///
/// Hits (`.podcast`, `.externalOnly`) are sticky forever.
/// Misses expire after 30 days so a podcast that gets indexed later
/// becomes discoverable on the next tap.
enum RecommendationMatch: Codable, Equatable {
    case podcast(uuid: String)
    case externalOnly(url: String)
    case miss(checkedAt: Date)
}
