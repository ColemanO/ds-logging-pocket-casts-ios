import Foundation

/// Builds typed sections from parsed CSV rows.
enum RecommendationsSectionBuilder {

    /// Matches divider rows like "Level 2 - 50 Hours" / "Level 6 - 1000 Hour".
    private static let levelRegex = try! NSRegularExpression(
        pattern: #"^Level\s+(\d+)\s*-\s*(\d+)\s*Hours?$"#,
        options: []
    )

    static func build(from rows: [[String]]) -> [RecommendationSection] {
        var sections: [RecommendationSection] = []
        var current: RecommendationSection?

        for row in rows {
            let firstColumn = (row.first ?? "").trimmingCharacters(in: .whitespaces)
            if firstColumn.isEmpty { continue }

            if let levelMatch = matchLevelHeader(firstColumn) {
                if let finished = current {
                    sections.append(finished)
                }
                current = RecommendationSection(
                    level: levelMatch.level,
                    title: firstColumn,
                    hourThreshold: levelMatch.hours,
                    recommendations: []
                )
                continue
            }

            guard current != nil else { continue }

            let title = firstColumn
            let location = column(row, 1).nonEmpty
            let mentions = Int(column(row, 2)) ?? 0
            let category = column(row, 3).nonEmpty
            let region = column(row, 4).nonEmpty
            let notes = column(row, 5).nonEmpty
            let otherLinks = column(row, 6).nonEmpty

            current?.recommendations.append(Recommendation(
                title: title,
                location: location,
                mentions: mentions,
                category: category,
                region: region,
                notes: notes,
                otherLinks: otherLinks
            ))
        }

        if let finished = current {
            sections.append(finished)
        }

        for index in sections.indices {
            sections[index].recommendations.sort(by: sortRule)
        }

        sections.sort { $0.level < $1.level }
        return sections
    }

    private struct LevelMatch {
        let level: Int
        let hours: Int
    }

    private static func matchLevelHeader(_ text: String) -> LevelMatch? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = levelRegex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges == 3,
              let levelRange = Range(match.range(at: 1), in: text),
              let hoursRange = Range(match.range(at: 2), in: text),
              let level = Int(text[levelRange]),
              let hours = Int(text[hoursRange])
        else {
            return nil
        }
        return LevelMatch(level: level, hours: hours)
    }

    private static func column(_ row: [String], _ index: Int) -> String {
        guard index < row.count else { return "" }
        return row[index].trimmingCharacters(in: .whitespaces)
    }

    private static func sortRule(_ a: Recommendation, _ b: Recommendation) -> Bool {
        if a.mentions == 0, b.mentions == 0 {
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
        if a.mentions == 0 { return false }
        if b.mentions == 0 { return true }
        if a.mentions != b.mentions { return a.mentions > b.mentions }
        return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
