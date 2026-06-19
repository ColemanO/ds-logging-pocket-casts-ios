import XCTest
@testable import podcasts

final class RecommendationFuzzyMatchTests: XCTestCase {

    func testExactMatch() {
        XCTAssertTrue(RecommendationFuzzyMatch.matches("Dreaming Spanish", "Dreaming Spanish"))
    }

    func testCaseInsensitive() {
        XCTAssertTrue(RecommendationFuzzyMatch.matches("dreaming spanish", "DREAMING SPANISH"))
    }

    func testDiacriticsIgnored() {
        XCTAssertTrue(RecommendationFuzzyMatch.matches("¡Cuéntame!", "Cuentame"))
    }

    func testPunctuationIgnored() {
        XCTAssertTrue(RecommendationFuzzyMatch.matches("Salsa!", "Salsa"))
    }

    func testWhitespaceCollapsed() {
        XCTAssertTrue(RecommendationFuzzyMatch.matches("  Spanish  After   Hours ", "Spanish After Hours"))
    }

    func testPrefixMatchAccepted() {
        XCTAssertTrue(RecommendationFuzzyMatch.matches(
            "Spanish with Alma",
            "Spanish with Alma | Real Conversations"
        ))
    }

    func testRejectsUnrelatedTitles() {
        XCTAssertFalse(RecommendationFuzzyMatch.matches("Dreaming Spanish", "Coffee Break Spanish"))
    }

    func testRejectsShortPrefixUnderSix() {
        XCTAssertFalse(RecommendationFuzzyMatch.matches("Spa", "Spanish with Alma"))
    }
}
