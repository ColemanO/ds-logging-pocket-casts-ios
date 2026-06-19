import XCTest
@testable import podcasts

final class RecommendationsCSVParserTests: XCTestCase {

    func testSimpleRow() {
        let rows = RecommendationsCSVParser.rows(from: "a,b,c\n1,2,3\n")
        XCTAssertEqual(rows, [["a", "b", "c"], ["1", "2", "3"]])
    }

    func testQuotedFieldWithComma() {
        let rows = RecommendationsCSVParser.rows(from: "\"a, b\",c\n")
        XCTAssertEqual(rows, [["a, b", "c"]])
    }

    func testDoubledQuotesInsideQuotedField() {
        let rows = RecommendationsCSVParser.rows(from: "\"He said \"\"hi\"\"\",x\n")
        XCTAssertEqual(rows, [["He said \"hi\"", "x"]])
    }

    func testEmbeddedNewlineInsideQuotedField() {
        let rows = RecommendationsCSVParser.rows(from: "\"line1\nline2\",y\n")
        XCTAssertEqual(rows, [["line1\nline2", "y"]])
    }

    func testCRLFLineEndings() {
        let rows = RecommendationsCSVParser.rows(from: "a,b\r\nc,d\r\n")
        XCTAssertEqual(rows, [["a", "b"], ["c", "d"]])
    }

    func testTrailingEmptyColumns() {
        let rows = RecommendationsCSVParser.rows(from: "a,,,\nb,c,,\n")
        XCTAssertEqual(rows, [["a", "", "", ""], ["b", "c", "", ""]])
    }

    func testNoTrailingNewline() {
        let rows = RecommendationsCSVParser.rows(from: "a,b")
        XCTAssertEqual(rows, [["a", "b"]])
    }

    func testEmptyInput() {
        XCTAssertEqual(RecommendationsCSVParser.rows(from: ""), [])
    }
}
