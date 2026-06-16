import XCTest
@testable import podcasts

final class RecommendationsSectionBuilderTests: XCTestCase {

    func testParsesLevelHeaderAndOneRow() {
        let rows: [[String]] = [
            ["Content", "Location", "Mentions", "Category", "Region", "Notes", "Other Links"],
            ["Level 1 - 0 Hours", "", "", "", "", "", ""],
            ["Dreaming Spanish", "YouTube", "823", "Comprehensible Input", "Spain", "", "https://x.com"]
        ]

        let sections = RecommendationsSectionBuilder.build(from: rows)

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].level, 1)
        XCTAssertEqual(sections[0].hourThreshold, 0)
        XCTAssertEqual(sections[0].title, "Level 1 - 0 Hours")
        XCTAssertEqual(sections[0].recommendations.count, 1)
        XCTAssertEqual(sections[0].recommendations[0].title, "Dreaming Spanish")
        XCTAssertEqual(sections[0].recommendations[0].location, "YouTube")
        XCTAssertEqual(sections[0].recommendations[0].mentions, 823)
        XCTAssertEqual(sections[0].recommendations[0].region, "Spain")
        XCTAssertEqual(sections[0].recommendations[0].otherLinks, "https://x.com")
    }

    func testBlankMentionsBecomesZero() {
        let rows: [[String]] = [
            ["Level 1 - 0 Hours"],
            ["Some Show", "Netflix", "", "", "", "", ""]
        ]
        let sections = RecommendationsSectionBuilder.build(from: rows)
        XCTAssertEqual(sections[0].recommendations[0].mentions, 0)
    }

    func testSortsRowsByMentionsDescBlanksToBottom() {
        let rows: [[String]] = [
            ["Level 1 - 0 Hours"],
            ["A", "", "5", "", "", "", ""],
            ["B", "", "", "", "", "", ""],
            ["C", "", "10", "", "", "", ""],
            ["D", "", "5", "", "", "", ""],
            ["E", "", "0", "", "", "", ""]
        ]
        let sections = RecommendationsSectionBuilder.build(from: rows)
        let titles = sections[0].recommendations.map(\.title)
        XCTAssertEqual(titles, ["C", "A", "D", "B", "E"])
    }

    func testSortsSectionsByLevel() {
        let rows: [[String]] = [
            ["Level 3 - 150 Hours"],
            ["X", "", "1", "", "", "", ""],
            ["Level 1 - 0 Hours"],
            ["Y", "", "1", "", "", "", ""],
            ["Level 2 - 50 Hours"],
            ["Z", "", "1", "", "", "", ""]
        ]
        let sections = RecommendationsSectionBuilder.build(from: rows)
        XCTAssertEqual(sections.map(\.level), [1, 2, 3])
    }

    func testIgnoresRowsBeforeFirstLevelHeader() {
        let rows: [[String]] = [
            ["Content", "Location", "Mentions"],
            ["Refold Resource Doc"],
            ["preamble row that should be skipped"],
            ["Level 1 - 0 Hours"],
            ["Good", "", "1", "", "", "", ""]
        ]
        let sections = RecommendationsSectionBuilder.build(from: rows)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].recommendations.count, 1)
        XCTAssertEqual(sections[0].recommendations[0].title, "Good")
    }

    func testEmptyContentRowIsSkipped() {
        let rows: [[String]] = [
            ["Level 1 - 0 Hours"],
            ["", "", "", "", "", "", ""],
            ["RealOne", "", "1", "", "", "", ""]
        ]
        let sections = RecommendationsSectionBuilder.build(from: rows)
        XCTAssertEqual(sections[0].recommendations.count, 1)
        XCTAssertEqual(sections[0].recommendations[0].title, "RealOne")
    }
}
