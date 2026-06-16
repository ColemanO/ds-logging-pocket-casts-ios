import Foundation

/// Confidence test for whether a Pocket Casts search result is the same
/// content as a recommendation row.
///
/// Strategy (intentionally conservative):
///   1. Normalize: lowercase, strip diacritics, drop punctuation, collapse
///      whitespace.
///   2. Accept iff the two normalized strings are equal, OR the shorter is
///      a prefix of the longer AND the shorter is at least 6 chars.
///
/// The prefix-of-length-≥-6 rule lets "Spanish with Alma" match
/// "Spanish with Alma | Real Conversations" (podcasts often add a subtitle
/// after a pipe) without false positives on tiny shared roots like "Spa"
/// vs "Spanish ...".
enum RecommendationFuzzyMatch {
    static func matches(_ a: String, _ b: String) -> Bool {
        let na = normalize(a)
        let nb = normalize(b)
        if na == nb { return true }
        let (shorter, longer) = na.count <= nb.count ? (na, nb) : (nb, na)
        guard shorter.count >= 6 else { return false }
        return longer.hasPrefix(shorter)
    }

    private static let allowedSet = CharacterSet.alphanumerics.union(.whitespaces)

    static func normalize(_ string: String) -> String {
        let folded = string.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let stripped = folded.unicodeScalars.filter { allowedSet.contains($0) }
        let collapsed = String(String.UnicodeScalarView(stripped))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed
    }
}
