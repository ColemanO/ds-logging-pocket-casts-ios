# Podcast Recommendations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Recommendations" view to the Podcasts tab that lists Spanish-learning content from a live Google Sheets CSV, sectioned by level, sorted by mentions, with lazy on-tap matching to Pocket Casts podcasts and a persistent on-disk match cache.

**Architecture:** A new SwiftUI subtree (`RecommendationsView` + supporting models/views) lives in `podcasts/Recommendations/`. A `RecommendationsRepository` singleton (`@MainActor`, `ObservableObject`) handles CSV fetch, parsing, on-disk caching (in `Caches/`), and lazy `PodcastSearchTask` matching. `PodcastListViewController` gets a UIKit segmented switcher above its existing collection view that toggles between Library and a `UIHostingController<RecommendationsView>`. The collection view's `contentInset.top` is bumped 44pt to make room for the switcher — no xib changes needed.

**Tech Stack:** Swift, SwiftUI, UIKit (`UIHostingController`, `UISegmentedControl`), `URLSession`, `JSONEncoder`/`Decoder`, `FileManager` (Caches dir), Pocket Casts' `PodcastSearchTask` and `ImageManager`, project theme system, project L10n build phase.

**Conventions to know:**
- Files added to `podcasts.xcodeproj/project.pbxproj` need 4 entries each: PBXBuildFile, PBXFileReference, group reference, Sources phase reference. Use the `1B0B5B__` prefix for new IDs (next free in this branch). Pattern: previous registrations from `ManualEntryKind.swift` used `1B0B5AF2/1B0B5AF3`. Follow that pattern: file ref `1B0B5BXX`, build file `1B0B5BXY`.
- L10n strings live in `podcasts/en.lproj/Localizable.strings`. `Strings+Generated.swift` is regenerated automatically by the build phase — never edit by hand; just add to `Localizable.strings` and the next build emits accessors.
- Swift formatter: `make format` after edits. CI runs SwiftLint.
- Build check command (used at end of every task):

  ```
  xcodebuild -project podcasts.xcodeproj -scheme pocketcasts -configuration Debug \
    -destination 'platform=iOS Simulator,id=7AB43694-2429-4444-BDC2-939523447581' \
    CODE_SIGNING_ALLOWED=NO build
  ```

  Look for `** BUILD SUCCEEDED **`.

- Theme: `@EnvironmentObject var theme: Theme` in SwiftUI views. Common keys: `primaryUi01` (page bg), `primaryUi02` (cell bg), `primaryText01/02`, `primaryInteractive01`, `support02`/`support05`.
- SwiftUI views hosted in UIKit use `ThemedHostingController<View>` (see `ManualEntriesViewController` for the right initialization pattern).

---

## Task 1: Add L10n strings

**Files:**
- Modify: `podcasts/en.lproj/Localizable.strings`

- [ ] **Step 1: Append new keys**

Open `podcasts/en.lproj/Localizable.strings` and append at the end of the file:

```
/* Podcasts tab — switcher: native library view */
"podcasts_library" = "Library";

/* Podcasts tab — switcher: recommendations from the community sheet */
"podcasts_recommendations" = "Recommendations";

/* Disambiguation sheet — title */
"recommendation_choose_podcast" = "Choose podcast";

/* Disambiguation sheet — bottom button to open the row's external link */
"recommendation_open_external" = "Open external link";

/* Recommendations — error retry button */
"recommendation_retry" = "Retry";

/* Recommendations — generic fetch error */
"recommendation_fetch_failed" = "Couldn't load recommendations. Check your connection and try again.";

/* Recommendations — empty disambiguation: no Pocket Casts results AND no external link */
"recommendation_no_match" = "No matching podcast found.";

/* Recommendations — empty list defensive copy */
"recommendations_empty" = "No recommendations available.";

/* Recommendations — mentions count accessibility label */
"recommendation_mentions_label" = "%@ mentions";
```

- [ ] **Step 2: Build to verify regeneration**

Run the build command above. The L10n build phase regenerates `Strings+Generated.swift` to include `L10n.podcastsLibrary`, `L10n.podcastsRecommendations`, `L10n.recommendationChoosePodcast`, `L10n.recommendationOpenExternal`, `L10n.recommendationRetry`, `L10n.recommendationFetchFailed`, `L10n.recommendationNoMatch`, `L10n.recommendationsEmpty`, `L10n.recommendationMentionsLabel`.

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add podcasts/en.lproj/Localizable.strings podcasts/Strings+Generated.swift
git commit -m "add L10n strings for podcast recommendations"
```

---

## Task 2: Create data model files

**Files:**
- Create: `podcasts/Recommendations/Recommendation.swift`
- Create: `podcasts/Recommendations/RecommendationMatch.swift`
- Modify: `podcasts.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create `Recommendation.swift`**

```swift
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
```

- [ ] **Step 2: Create `RecommendationMatch.swift`**

```swift
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
```

- [ ] **Step 3: Register both files in pbxproj**

In `podcasts.xcodeproj/project.pbxproj`, search for the `ManualEntryKind.swift` entries to find the patterns. Add the following blocks (use IDs `1B0B5B00/1B0B5B01` for Recommendation.swift and `1B0B5B02/1B0B5B03` for RecommendationMatch.swift):

**a) Verify IDs are unused.** Search the file for `1B0B5B0`. If anything matches, increment the prefix until clean (e.g. `1B0B5B10`).

**b) PBXBuildFile section** (search for `/* Begin PBXBuildFile section */`):

```
		1B0B5B01 /* Recommendation.swift in Sources */ = {isa = PBXBuildFile; fileRef = 1B0B5B00 /* Recommendation.swift */; };
		1B0B5B03 /* RecommendationMatch.swift in Sources */ = {isa = PBXBuildFile; fileRef = 1B0B5B02 /* RecommendationMatch.swift */; };
```

**c) PBXFileReference section** (search for `/* Begin PBXFileReference section */`):

```
		1B0B5B00 /* Recommendation.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Recommendation.swift; sourceTree = "<group>"; };
		1B0B5B02 /* RecommendationMatch.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = RecommendationMatch.swift; sourceTree = "<group>"; };
```

**d) Group entry.** Search for the `Dreaming` group in PBXGroup. We need a new `Recommendations` group at the same level. Find the parent group (likely `podcasts` group). Add a new group entry:

```
		1B0B5BFA /* Recommendations */ = {
			isa = PBXGroup;
			children = (
				1B0B5B00 /* Recommendation.swift */,
				1B0B5B02 /* RecommendationMatch.swift */,
			);
			path = Recommendations;
			sourceTree = "<group>";
		};
```

And add `1B0B5BFA /* Recommendations */,` to the parent `podcasts` group's children list, alphabetically adjacent to the `Dreaming` group entry.

**e) Sources phase.** Search for `/* Begin PBXSourcesBuildPhase section */`. Inside the main app's `files = (` list, add:

```
				1B0B5B01 /* Recommendation.swift in Sources */,
				1B0B5B03 /* RecommendationMatch.swift in Sources */,
```

- [ ] **Step 4: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

If the project file is malformed, Xcode will refuse to load. Open `podcasts.xcodeproj` in Xcode to confirm visually that `Recommendations/` group appears with both files inside, then close.

- [ ] **Step 5: Format**

```bash
make format
```

- [ ] **Step 6: Commit**

```bash
git add podcasts/Recommendations/Recommendation.swift podcasts/Recommendations/RecommendationMatch.swift podcasts.xcodeproj/project.pbxproj
git commit -m "add Recommendation and RecommendationMatch models"
```

---

## Task 3: Create CSV parser with unit tests

**Files:**
- Create: `podcasts/Recommendations/RecommendationsCSVParser.swift`
- Create: `PocketCastsTests/Tests/Recommendations/RecommendationsCSVParserTests.swift`
- Modify: `podcasts.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing test**

Create directory `PocketCastsTests/Tests/Recommendations/` then create `RecommendationsCSVParserTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild -project podcasts.xcodeproj -scheme pocketcasts -configuration Debug \
  -destination 'platform=iOS Simulator,id=7AB43694-2429-4444-BDC2-939523447581' \
  -only-testing:PocketCastsTests/RecommendationsCSVParserTests \
  CODE_SIGNING_ALLOWED=NO test 2>&1 | tail -20
```

Expected: Build fails because `RecommendationsCSVParser` doesn't exist yet.

- [ ] **Step 3: Implement the parser**

Create `podcasts/Recommendations/RecommendationsCSVParser.swift`:

```swift
import Foundation

/// Minimal CSV parser for the Refold Resource Doc export.
///
/// Handles:
///   - Quoted fields with embedded commas and newlines.
///   - Doubled quotes inside quoted fields ("" → ").
///   - LF and CRLF line endings.
///   - Trailing empty columns and missing trailing newline.
enum RecommendationsCSVParser {
    static func rows(from text: String) -> [[String]] {
        var rows: [[String]] = []
        var current: [String] = []
        var field = ""
        var inQuotes = false
        var i = text.startIndex

        while i < text.endIndex {
            let c = text[i]

            if inQuotes {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        i = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"":
                    inQuotes = true
                case ",":
                    current.append(field)
                    field = ""
                case "\r":
                    // swallow; the following "\n" closes the row
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\n" {
                        i = next
                    }
                    current.append(field)
                    rows.append(current)
                    current = []
                    field = ""
                case "\n":
                    current.append(field)
                    rows.append(current)
                    current = []
                    field = ""
                default:
                    field.append(c)
                }
            }

            i = text.index(after: i)
        }

        if !field.isEmpty || !current.isEmpty {
            current.append(field)
            rows.append(current)
        }

        return rows
    }
}
```

- [ ] **Step 4: Register the source file in pbxproj**

Use IDs `1B0B5B04/1B0B5B05`. Same 4 places as Task 2 (PBXBuildFile, PBXFileReference, group children, Sources phase):

```
		1B0B5B05 /* RecommendationsCSVParser.swift in Sources */ = {isa = PBXBuildFile; fileRef = 1B0B5B04 /* RecommendationsCSVParser.swift */; };
```
```
		1B0B5B04 /* RecommendationsCSVParser.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = RecommendationsCSVParser.swift; sourceTree = "<group>"; };
```

Add `1B0B5B04 /* RecommendationsCSVParser.swift */,` to the `1B0B5BFA /* Recommendations */` group's children.

Add `1B0B5B05 /* RecommendationsCSVParser.swift in Sources */,` to the main app's Sources phase.

- [ ] **Step 5: Register the test file in pbxproj**

The test target uses a different group structure. Search for an existing test file like `ShowNotesFormatterUtilsTests.swift` to find:
- Its PBXBuildFile entry, which sits in a *different* Sources phase (`PocketCastsTests` target's PBXSourcesBuildPhase). Find it.
- Its PBXFileReference entry.
- Its group entry under `PocketCastsTests` group.

Use IDs `1B0B5B06/1B0B5B07`. Add:

**PBXBuildFile (in `PocketCastsTests` Sources phase block — there are multiple Sources phases in the file; pick the one whose buildActionMask shows test files):**

```
		1B0B5B07 /* RecommendationsCSVParserTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = 1B0B5B06 /* RecommendationsCSVParserTests.swift */; };
```

**PBXFileReference:**

```
		1B0B5B06 /* RecommendationsCSVParserTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = RecommendationsCSVParserTests.swift; sourceTree = "<group>"; };
```

**Group:** Create a new `Recommendations` subgroup under `PocketCastsTests/Tests/` group:

```
		1B0B5BFB /* Recommendations */ = {
			isa = PBXGroup;
			children = (
				1B0B5B06 /* RecommendationsCSVParserTests.swift */,
			);
			path = Recommendations;
			sourceTree = "<group>";
		};
```

Add `1B0B5BFB /* Recommendations */,` to the `Tests` group's children list under PocketCastsTests.

**Sources phase:** add to the PocketCastsTests Sources phase files list:

```
				1B0B5B07 /* RecommendationsCSVParserTests.swift in Sources */,
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
xcodebuild -project podcasts.xcodeproj -scheme pocketcasts -configuration Debug \
  -destination 'platform=iOS Simulator,id=7AB43694-2429-4444-BDC2-939523447581' \
  -only-testing:PocketCastsTests/RecommendationsCSVParserTests \
  CODE_SIGNING_ALLOWED=NO test 2>&1 | tail -30
```

Expected: All 8 tests pass.

- [ ] **Step 7: Format**

```bash
make format
```

- [ ] **Step 8: Commit**

```bash
git add podcasts/Recommendations/RecommendationsCSVParser.swift \
        PocketCastsTests/Tests/Recommendations/RecommendationsCSVParserTests.swift \
        podcasts.xcodeproj/project.pbxproj
git commit -m "add CSV parser for recommendations sheet"
```

---

## Task 4: Create section builder with unit tests

**Files:**
- Create: `podcasts/Recommendations/RecommendationsSectionBuilder.swift`
- Create: `PocketCastsTests/Tests/Recommendations/RecommendationsSectionBuilderTests.swift`
- Modify: `podcasts.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing test**

Create `PocketCastsTests/Tests/Recommendations/RecommendationsSectionBuilderTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild -project podcasts.xcodeproj -scheme pocketcasts -configuration Debug \
  -destination 'platform=iOS Simulator,id=7AB43694-2429-4444-BDC2-939523447581' \
  -only-testing:PocketCastsTests/RecommendationsSectionBuilderTests \
  CODE_SIGNING_ALLOWED=NO test 2>&1 | tail -20
```

Expected: Build fails — `RecommendationsSectionBuilder` doesn't exist.

- [ ] **Step 3: Implement the section builder**

Create `podcasts/Recommendations/RecommendationsSectionBuilder.swift`:

```swift
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
```

- [ ] **Step 4: Register source file in pbxproj**

Use IDs `1B0B5B08/1B0B5B09`. Add 4 entries (build file, file ref, Recommendations group child, app target Sources phase) as in earlier tasks.

- [ ] **Step 5: Register test file in pbxproj**

Use IDs `1B0B5B0A/1B0B5B0B`. Add 4 entries for the test (build file, file ref, PocketCastsTests Recommendations group child, test target Sources phase).

- [ ] **Step 6: Run the test to verify it passes**

```bash
xcodebuild -project podcasts.xcodeproj -scheme pocketcasts -configuration Debug \
  -destination 'platform=iOS Simulator,id=7AB43694-2429-4444-BDC2-939523447581' \
  -only-testing:PocketCastsTests/RecommendationsSectionBuilderTests \
  CODE_SIGNING_ALLOWED=NO test 2>&1 | tail -30
```

Expected: All 6 tests pass.

- [ ] **Step 7: Format and commit**

```bash
make format
git add podcasts/Recommendations/RecommendationsSectionBuilder.swift \
        PocketCastsTests/Tests/Recommendations/RecommendationsSectionBuilderTests.swift \
        podcasts.xcodeproj/project.pbxproj
git commit -m "add recommendations section builder"
```

---

## Task 5: Create fuzzy match helper with unit tests

**Files:**
- Create: `podcasts/Recommendations/RecommendationFuzzyMatch.swift`
- Create: `PocketCastsTests/Tests/Recommendations/RecommendationFuzzyMatchTests.swift`
- Modify: `podcasts.xcodeproj/project.pbxproj`

The plan starts with the simpler "normalized equality OR shorter is a prefix of the longer of length ≥ 6". Jaro-Winkler can be added later if smoke testing reveals false negatives.

- [ ] **Step 1: Write the failing test**

```swift
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
        // sheet title is shorter, podcast title has a subtitle
        XCTAssertTrue(RecommendationFuzzyMatch.matches(
            "Spanish with Alma",
            "Spanish with Alma | Real Conversations"
        ))
    }

    func testRejectsUnrelatedTitles() {
        XCTAssertFalse(RecommendationFuzzyMatch.matches("Dreaming Spanish", "Coffee Break Spanish"))
    }

    func testRejectsShortPrefixUnderSix() {
        // "Spa" is only 3 chars normalized — too short to be a confident prefix
        XCTAssertFalse(RecommendationFuzzyMatch.matches("Spa", "Spanish with Alma"))
    }
}
```

- [ ] **Step 2: Verify the test fails**

```bash
xcodebuild ... -only-testing:PocketCastsTests/RecommendationFuzzyMatchTests test 2>&1 | tail -20
```

Expected: build fails — symbol missing.

- [ ] **Step 3: Implement the matcher**

Create `podcasts/Recommendations/RecommendationFuzzyMatch.swift`:

```swift
import Foundation

/// Confidence test for whether a Pocket Casts search result is the same
/// content as a recommendation row.
///
/// Strategy (intentionally conservative):
///   1. Normalize: lowercase, strip diacritics, drop punctuation, collapse
///      whitespace.
///   2. Accept iff the two normalized strings are equal, OR the shorter is
///      a proper prefix of the longer AND the shorter is at least 6 chars.
///
/// The prefix-of-length-≥-6 rule lets `"Spanish with Alma"` match
/// `"Spanish with Alma | Real Conversations"` (podcasts often add a
/// subtitle after a pipe) without false positives on tiny shared roots
/// like "Spa" vs "Spanish ...".
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
```

- [ ] **Step 4: Register source + test in pbxproj**

Source IDs: `1B0B5B0C/1B0B5B0D`. Test IDs: `1B0B5B0E/1B0B5B0F`. Add 4 entries per file as before.

- [ ] **Step 5: Run tests**

```bash
xcodebuild ... -only-testing:PocketCastsTests/RecommendationFuzzyMatchTests test 2>&1 | tail -30
```

Expected: 8 tests pass.

- [ ] **Step 6: Format and commit**

```bash
make format
git add podcasts/Recommendations/RecommendationFuzzyMatch.swift \
        PocketCastsTests/Tests/Recommendations/RecommendationFuzzyMatchTests.swift \
        podcasts.xcodeproj/project.pbxproj
git commit -m "add fuzzy match helper for recommendations"
```

---

## Task 6: Create RecommendationsRepository

**Files:**
- Create: `podcasts/Recommendations/RecommendationsRepository.swift`
- Modify: `podcasts.xcodeproj/project.pbxproj`

This task is large but cohesive — the repository is one file with fetch, cache, and resolve responsibilities. No unit tests here; the file is dominated by I/O and async behavior. Verification is by build success + smoke testing in Task 11.

- [ ] **Step 1: Create the file**

`podcasts/Recommendations/RecommendationsRepository.swift`:

```swift
import Foundation
import PocketCastsServer
import PocketCastsUtils

/// Resolution returned by `RecommendationsRepository.resolve(for:)`.
/// Transient, not persisted. The persisted form is `RecommendationMatch`.
enum RecommendationResolution {
    case podcast(uuid: String)
    case externalOnly(url: String)
    case needsDisambiguation(results: [PodcastFolderSearchResult], externalURL: URL?)
    case noOptions
}

enum RecommendationsError: Error {
    case fetchFailed
    case decodingFailed
}

@MainActor
final class RecommendationsRepository: ObservableObject {
    static let shared = RecommendationsRepository()

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(message: String)
    }

    @Published private(set) var snapshot: RecommendationsSnapshot?
    @Published private(set) var matches: [String: RecommendationMatch] = [:]
    @Published private(set) var loadState: LoadState = .idle

    private let csvURL = URL(string:
        "https://docs.google.com/spreadsheets/d/1lBmLxvWJpucXhRPayfXD7CVqpMoa2tyEbZi1rFAwsFs/export?format=csv&gid=0"
    )!

    private let missTTL: TimeInterval = 30 * 86_400
    private let snapshotMaxAge: TimeInterval = 3_600

    private var inFlightFetch: Task<Void, Never>?
    private var didLoadCaches = false

    private init() {}

    // MARK: - Public API

    func loadOnAppear() async {
        loadCachesFromDiskIfNeeded()

        if snapshot != nil {
            loadState = .loaded
            if let fetchedAt = snapshot?.fetchedAt,
               Date().timeIntervalSince(fetchedAt) > snapshotMaxAge {
                backgroundRefresh()
            }
        } else {
            loadState = .loading
            await foregroundFetch()
        }
    }

    func refresh() async {
        await foregroundFetch(forceUserSurface: true)
    }

    func resolve(for rec: Recommendation) async -> RecommendationResolution {
        loadCachesFromDiskIfNeeded()

        if let cached = matches[rec.matchKey] {
            switch cached {
            case .podcast(let uuid):
                return .podcast(uuid: uuid)
            case .externalOnly(let url):
                return .externalOnly(url: url)
            case .miss(let checkedAt) where Date().timeIntervalSince(checkedAt) <= missTTL:
                if let ext = externalURL(for: rec) {
                    return .needsDisambiguation(results: [], externalURL: ext)
                } else {
                    return .noOptions
                }
            case .miss:
                break // expired; re-search
            }
        }

        let results: [PodcastFolderSearchResult]
        do {
            results = try await PodcastSearchTask().search(term: rec.title)
        } catch {
            if let ext = externalURL(for: rec) {
                return .needsDisambiguation(results: [], externalURL: ext)
            } else {
                return .noOptions
            }
        }

        if let top = results.first, RecommendationFuzzyMatch.matches(rec.title, top.title) {
            matches[rec.matchKey] = .podcast(uuid: top.uuid)
            persistMatches()
            return .podcast(uuid: top.uuid)
        }

        let ext = externalURL(for: rec)
        if results.isEmpty, ext == nil {
            matches[rec.matchKey] = .miss(checkedAt: Date())
            persistMatches()
            return .noOptions
        }
        return .needsDisambiguation(results: results, externalURL: ext)
    }

    func overrideMatch(_ match: RecommendationMatch, for rec: Recommendation) {
        matches[rec.matchKey] = match
        persistMatches()
    }

    func cachedMatch(for rec: Recommendation) -> RecommendationMatch? {
        loadCachesFromDiskIfNeeded()
        return matches[rec.matchKey]
    }

    // MARK: - Disk cache

    private var cachesDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }
    private var snapshotFile: URL { cachesDir.appendingPathComponent("recommendations_csv.json") }
    private var matchesFile: URL { cachesDir.appendingPathComponent("recommendations_matches.json") }

    private func loadCachesFromDiskIfNeeded() {
        guard !didLoadCaches else { return }
        didLoadCaches = true
        loadSnapshotFromDisk()
        loadMatchesFromDisk()
    }

    private func loadSnapshotFromDisk() {
        guard let data = try? Data(contentsOf: snapshotFile),
              let decoded = try? JSONDecoder().decode(RecommendationsSnapshot.self, from: data)
        else {
            return
        }
        snapshot = decoded
    }

    private func loadMatchesFromDisk() {
        guard let data = try? Data(contentsOf: matchesFile),
              let decoded = try? JSONDecoder().decode([String: RecommendationMatch].self, from: data)
        else {
            return
        }
        matches = decoded
    }

    private func persistSnapshot(_ snapshot: RecommendationsSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: snapshotFile, options: .atomic)
    }

    private func persistMatches() {
        guard let data = try? JSONEncoder().encode(matches) else { return }
        try? data.write(to: matchesFile, options: .atomic)
    }

    // MARK: - Fetch

    private func foregroundFetch(forceUserSurface: Bool = false) async {
        do {
            let fresh = try await fetchCSV()
            snapshot = fresh
            persistSnapshot(fresh)
            loadState = .loaded
        } catch {
            if snapshot == nil {
                loadState = .failed(message: L10n.recommendationFetchFailed)
            } else if forceUserSurface {
                // refresh failed with cached data on screen — leave loadState alone;
                // the view surfaces a transient toast via its own state.
                loadState = .loaded
            } else {
                loadState = .loaded
            }
        }
    }

    private func backgroundRefresh() {
        inFlightFetch?.cancel()
        inFlightFetch = Task { [weak self] in
            guard let self else { return }
            do {
                let fresh = try await self.fetchCSV()
                self.snapshot = fresh
                self.persistSnapshot(fresh)
            } catch {
                // Silent. Stale cache stays visible.
            }
        }
    }

    private func fetchCSV() async throws -> RecommendationsSnapshot {
        let (data, response) = try await URLSession.shared.data(from: csvURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RecommendationsError.fetchFailed
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw RecommendationsError.decodingFailed
        }
        let rows = RecommendationsCSVParser.rows(from: text)
        let sections = RecommendationsSectionBuilder.build(from: rows)
        return RecommendationsSnapshot(fetchedAt: Date(), sections: sections)
    }

    // MARK: - External link parsing

    private func externalURL(for rec: Recommendation) -> URL? {
        guard let raw = rec.otherLinks?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return nil
        }
        let candidates = raw.components(separatedBy: CharacterSet(charactersIn: " ,\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return candidates.compactMap { URL(string: $0) }.first
    }
}
```

- [ ] **Step 2: Register in pbxproj**

IDs `1B0B5B10/1B0B5B11`. 4 entries as before.

- [ ] **Step 3: Build**

Run the full build command. Expected: `** BUILD SUCCEEDED **`.

If `PodcastSearchTask` or `PodcastFolderSearchResult` doesn't import cleanly, double-check that `PocketCastsServer` is added as an import (it should already be in the file).

- [ ] **Step 4: Format and commit**

```bash
make format
git add podcasts/Recommendations/RecommendationsRepository.swift podcasts.xcodeproj/project.pbxproj
git commit -m "add RecommendationsRepository with CSV fetch, cache, and resolve"
```

---

## Task 7: Create RecommendationRow view

**Files:**
- Create: `podcasts/Recommendations/RecommendationRow.swift`
- Modify: `podcasts.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

struct RecommendationRow: View {
    @EnvironmentObject var theme: Theme
    let rec: Recommendation

    @State private var matchedUUID: String?

    var body: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(rec.title)
                    .font(.body)
                    .foregroundColor(theme.primaryText01)
                    .lineLimit(1)
                if let region = rec.region, !region.isEmpty {
                    Text(region)
                        .font(.caption)
                        .foregroundColor(theme.primaryText02)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if rec.mentions > 0 {
                mentionsBadge
            }
        }
        .padding(.vertical, 4)
        .task { matchedUUID = resolveCachedUUID() }
    }

    @ViewBuilder
    private var artwork: some View {
        if let uuid = matchedUUID {
            PodcastArtworkView(uuid: uuid)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.primaryUi02)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "mic.fill")
                        .foregroundColor(theme.primaryText02)
                )
        }
    }

    private var mentionsBadge: some View {
        Text("\(rec.mentions)")
            .font(.caption.weight(.semibold))
            .foregroundColor(theme.primaryText01)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(theme.primaryUi02)
            )
            .accessibilityLabel(String(format: L10n.recommendationMentionsLabel, "\(rec.mentions)"))
    }

    private func resolveCachedUUID() -> String? {
        guard case .podcast(let uuid) = RecommendationsRepository.shared.cachedMatch(for: rec) else {
            return nil
        }
        return uuid
    }
}

/// Bridges UIKit `ImageManager` artwork loading into SwiftUI.
private struct PodcastArtworkView: UIViewRepresentable {
    let uuid: String

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        ImageManager.sharedManager.loadImage(podcastUuid: uuid, imageView: view, size: .list, showPlaceHolder: true)
        return view
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        ImageManager.sharedManager.loadImage(podcastUuid: uuid, imageView: uiView, size: .list, showPlaceHolder: true)
    }
}
```

> **Implementation note:** the exact `ImageManager.sharedManager.loadImage(...)` signature may differ. Open `podcasts/ImageManager.swift` (or grep for `loadImage(podcastUuid:`) and adjust the call to match the existing signature. Pick the smallest available size.

- [ ] **Step 2: Register in pbxproj**

IDs `1B0B5B12/1B0B5B13`.

- [ ] **Step 3: Build**

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Format and commit**

```bash
make format
git add podcasts/Recommendations/RecommendationRow.swift podcasts.xcodeproj/project.pbxproj
git commit -m "add RecommendationRow view"
```

---

## Task 8: Create RecommendationDisambiguationView

**Files:**
- Create: `podcasts/Recommendations/RecommendationDisambiguationView.swift`
- Modify: `podcasts.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create the file**

```swift
import SwiftUI
import PocketCastsServer

struct RecommendationDisambiguationPayload: Identifiable, Equatable {
    let id = UUID()
    let rec: Recommendation
    let results: [PodcastFolderSearchResult]
    let externalURL: URL?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

struct RecommendationDisambiguationView: View {
    @EnvironmentObject var theme: Theme
    @Environment(\.dismiss) private var dismiss

    let payload: RecommendationDisambiguationPayload
    let onPodcastChosen: (String) -> Void
    let onExternalChosen: (URL) -> Void

    var body: some View {
        NavigationView {
            ZStack {
                theme.primaryUi01.ignoresSafeArea()
                List {
                    Section {
                        Text(payload.rec.title)
                            .font(.headline)
                            .foregroundColor(theme.primaryText01)
                            .listRowBackground(theme.primaryUi02)
                    }

                    if !payload.results.isEmpty {
                        Section {
                            ForEach(payload.results.prefix(5), id: \.uuid) { result in
                                Button(action: { choosePodcast(uuid: result.uuid) }) {
                                    HStack(spacing: 12) {
                                        DisambiguationArtwork(uuid: result.uuid)
                                            .frame(width: 44, height: 44)
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(result.title)
                                                .font(.body)
                                                .foregroundColor(theme.primaryText01)
                                                .lineLimit(1)
                                            if let author = result.author, !author.isEmpty {
                                                Text(author)
                                                    .font(.caption)
                                                    .foregroundColor(theme.primaryText02)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                    }
                                }
                                .listRowBackground(theme.primaryUi02)
                            }
                        }
                    }

                    if let extURL = payload.externalURL {
                        Section {
                            Button(action: { chooseExternal(url: extURL) }) {
                                HStack {
                                    Image(systemName: "arrow.up.right.square")
                                        .foregroundColor(theme.primaryInteractive01)
                                    Text(L10n.recommendationOpenExternal)
                                        .foregroundColor(theme.primaryInteractive01)
                                    Spacer()
                                }
                            }
                            .listRowBackground(theme.primaryUi02)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(L10n.recommendationChoosePodcast)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                        .foregroundColor(theme.primaryInteractive01)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func choosePodcast(uuid: String) {
        onPodcastChosen(uuid)
        dismiss()
    }

    private func chooseExternal(url: URL) {
        onExternalChosen(url)
        dismiss()
    }
}

private struct DisambiguationArtwork: UIViewRepresentable {
    let uuid: String

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        ImageManager.sharedManager.loadImage(podcastUuid: uuid, imageView: view, size: .list, showPlaceHolder: true)
        return view
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        ImageManager.sharedManager.loadImage(podcastUuid: uuid, imageView: uiView, size: .list, showPlaceHolder: true)
    }
}
```

> If `result.author` doesn't compile (different field name), grep `PodcastFolderSearchResult` for the correct accessor. If `L10n.cancel` doesn't exist, use the existing close string (search `L10n` for "Close" or "Cancel"; the typed-manual-entries spec used `L10n.close`).

- [ ] **Step 2: Register in pbxproj**

IDs `1B0B5B14/1B0B5B15`.

- [ ] **Step 3: Build**

Expected: `** BUILD SUCCEEDED **`. Fix any field-name mismatches discovered.

- [ ] **Step 4: Format and commit**

```bash
make format
git add podcasts/Recommendations/RecommendationDisambiguationView.swift podcasts.xcodeproj/project.pbxproj
git commit -m "add disambiguation sheet for recommendation matches"
```

---

## Task 9: Create RecommendationsView

**Files:**
- Create: `podcasts/Recommendations/RecommendationsView.swift`
- Modify: `podcasts.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create the file**

```swift
import SwiftUI
import PocketCastsServer

struct RecommendationsView: View {
    @EnvironmentObject var theme: Theme
    @StateObject private var repo = RecommendationsRepository.shared
    @State private var expandedSections: Set<Int> = []
    @State private var disambiguation: RecommendationDisambiguationPayload?
    @State private var showNoMatchAlert = false
    @State private var showRefreshFailure = false

    var body: some View {
        ZStack {
            theme.primaryUi01.ignoresSafeArea()
            content
        }
        .task {
            await repo.loadOnAppear()
            initializeExpansionIfNeeded()
        }
        .refreshable {
            await repo.refresh()
            initializeExpansionIfNeeded()
        }
        .sheet(item: $disambiguation) { payload in
            RecommendationDisambiguationView(
                payload: payload,
                onPodcastChosen: { uuid in
                    repo.overrideMatch(.podcast(uuid: uuid), for: payload.rec)
                    NavigationManager.sharedManager.navigateTo(
                        NavigationManager.podcastPageKey,
                        data: [NavigationManager.podcastKey: uuid]
                    )
                },
                onExternalChosen: { url in
                    repo.overrideMatch(.externalOnly(url: url.absoluteString), for: payload.rec)
                    UIApplication.shared.open(url)
                }
            )
            .environmentObject(theme)
        }
        .alert(L10n.recommendationNoMatch, isPresented: $showNoMatchAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var content: some View {
        switch repo.loadState {
        case .idle, .loading:
            ProgressView().tint(theme.primaryInteractive01)
        case .failed(let message):
            errorView(message)
        case .loaded:
            if let sections = repo.snapshot?.sections, !sections.isEmpty {
                list(sections: sections)
            } else {
                Text(L10n.recommendationsEmpty)
                    .foregroundColor(theme.primaryText02)
            }
        }
    }

    private func list(sections: [RecommendationSection]) -> some View {
        List {
            ForEach(sections) { section in
                Section {
                    if expandedSections.contains(section.level) {
                        ForEach(section.recommendations) { rec in
                            RecommendationRow(rec: rec)
                                .listRowBackground(theme.primaryUi02)
                                .contentShape(Rectangle())
                                .onTapGesture { handleTap(rec) }
                        }
                    }
                } header: {
                    sectionHeader(section)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func sectionHeader(_ section: RecommendationSection) -> some View {
        Button(action: { toggleSection(section.level) }) {
            HStack {
                Text(section.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(theme.primaryText02)
                Spacer()
                Image(systemName: expandedSections.contains(section.level) ? "chevron.down" : "chevron.right")
                    .foregroundColor(theme.primaryText02)
                    .font(.caption.weight(.bold))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text(message)
                .foregroundColor(theme.primaryText01)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(L10n.recommendationRetry) {
                Task { await repo.refresh() }
            }
            .foregroundColor(theme.primaryInteractive01)
            .fontWeight(.semibold)
        }
    }

    // MARK: - Actions

    private func toggleSection(_ level: Int) {
        if expandedSections.contains(level) {
            expandedSections.remove(level)
        } else {
            expandedSections.insert(level)
        }
    }

    private func handleTap(_ rec: Recommendation) {
        Task {
            let outcome = await repo.resolve(for: rec)
            switch outcome {
            case .podcast(let uuid):
                NavigationManager.sharedManager.navigateTo(
                    NavigationManager.podcastPageKey,
                    data: [NavigationManager.podcastKey: uuid]
                )
            case .externalOnly(let urlString):
                if let url = URL(string: urlString) {
                    UIApplication.shared.open(url)
                }
            case .needsDisambiguation(let results, let externalURL):
                disambiguation = RecommendationDisambiguationPayload(
                    rec: rec, results: results, externalURL: externalURL
                )
            case .noOptions:
                showNoMatchAlert = true
            }
        }
    }

    // MARK: - Section expansion

    private func initializeExpansionIfNeeded() {
        guard expandedSections.isEmpty, let sections = repo.snapshot?.sections else { return }
        let totalHours = DreamingManager.shared.cachedTotalInputSeconds / 3600
        if totalHours <= 0 {
            expandedSections = Set(sections.map(\.level))
            return
        }
        let userLevel = sections
            .filter { Double($0.hourThreshold) <= totalHours }
            .map(\.level)
            .max() ?? 1
        expandedSections = Set(sections.filter { $0.level <= userLevel }.map(\.level))
        if expandedSections.isEmpty {
            expandedSections = Set(sections.map(\.level))
        }
    }
}
```

> **Implementation note:** `DreamingManager.shared.cachedTotalInputSeconds` — verify this property exists with that exact name. Grep `DreamingManager` for `cachedTotal` if not. The previous typed-manual-entries spec referenced this; if the actual property is named differently, update the call site.

- [ ] **Step 2: Register in pbxproj**

IDs `1B0B5B16/1B0B5B17`.

- [ ] **Step 3: Build**

Expected: `** BUILD SUCCEEDED **`. Fix any property-name mismatches.

- [ ] **Step 4: Format and commit**

```bash
make format
git add podcasts/Recommendations/RecommendationsView.swift podcasts.xcodeproj/project.pbxproj
git commit -m "add RecommendationsView with sections and disambiguation flow"
```

---

## Task 10: Wire switcher into PodcastListViewController

**Files:**
- Modify: `podcasts/PodcastListViewController.swift`

The strategy: add a 44pt-tall `UISegmentedControl` container as a sibling of the existing collection view, anchored to the safe area top. Bump `podcastsCollectionView.contentInset.top` (and scroll-indicator inset) by 44 so the library content visually starts below the switcher. The collection view itself still extends behind the switcher — that's fine because the switcher container has an opaque background. Embed a `UIHostingController<RecommendationsView>` whose `view` is constrained to the same edges as the collection view (top to switcher-bottom, leading/trailing/bottom to view safe-area / view bottom).

- [ ] **Step 1: Add state, switcher, and child hosting controller**

Add these new properties on `PodcastListViewController`, just above `var gridItems = [HomeGridListItem]()`:

```swift
private enum ActiveView: Int {
    case library = 0
    case recommendations = 1
}

private static let activeViewDefaultsKey = "PodcastsTabActiveView"
private let switcherHeight: CGFloat = 44

private lazy var switcherContainer: UIView = {
    let view = ThemeableView()
    view.style = .primaryUi01
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
}()

private lazy var switcher: UISegmentedControl = {
    let control = UISegmentedControl(items: [L10n.podcastsLibrary, L10n.podcastsRecommendations])
    control.translatesAutoresizingMaskIntoConstraints = false
    control.selectedSegmentIndex = UserDefaults.standard.integer(forKey: Self.activeViewDefaultsKey)
    control.addTarget(self, action: #selector(switcherChanged(_:)), for: .valueChanged)
    return control
}()

private lazy var recommendationsHost: UIHostingController<AnyView> = {
    let theme = Theme.sharedTheme
    let root = AnyView(RecommendationsView().environmentObject(theme))
    let host = UIHostingController(rootView: root)
    host.view.translatesAutoresizingMaskIntoConstraints = false
    return host
}()
```

> If `Theme.sharedTheme` isn't the right accessor in this project, grep for `Theme()` in another ThemedHostingController to find how an instance is obtained.

- [ ] **Step 2: Set up the switcher in `viewDidLoad`**

Modify `viewDidLoad`. Add the following at the end of the method, after `insetAdjuster.setupInsetAdjustmentsForMiniPlayer(scrollView: podcastsCollectionView)`:

```swift
setupSwitcher()
applyActiveView(ActiveView(rawValue: switcher.selectedSegmentIndex) ?? .library)
```

Add a new method below `viewDidLoad`:

```swift
private func setupSwitcher() {
    view.addSubview(switcherContainer)
    switcherContainer.addSubview(switcher)

    addChild(recommendationsHost)
    view.addSubview(recommendationsHost.view)
    recommendationsHost.didMove(toParent: self)
    recommendationsHost.view.isHidden = true

    NSLayoutConstraint.activate([
        switcherContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
        switcherContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        switcherContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        switcherContainer.heightAnchor.constraint(equalToConstant: switcherHeight),

        switcher.centerXAnchor.constraint(equalTo: switcherContainer.centerXAnchor),
        switcher.centerYAnchor.constraint(equalTo: switcherContainer.centerYAnchor),
        switcher.widthAnchor.constraint(lessThanOrEqualTo: switcherContainer.widthAnchor, constant: -32),

        recommendationsHost.view.topAnchor.constraint(equalTo: switcherContainer.bottomAnchor),
        recommendationsHost.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
        recommendationsHost.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        recommendationsHost.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])

    // The library collection view extends behind the switcher; offset its content.
    podcastsCollectionView.contentInset.top += switcherHeight
    podcastsCollectionView.verticalScrollIndicatorInsets.top += switcherHeight

    // Make sure the switcher container renders ON TOP of the collection view.
    view.bringSubviewToFront(switcherContainer)
}

@objc private func switcherChanged(_ sender: UISegmentedControl) {
    let active = ActiveView(rawValue: sender.selectedSegmentIndex) ?? .library
    UserDefaults.standard.set(sender.selectedSegmentIndex, forKey: Self.activeViewDefaultsKey)
    applyActiveView(active)
}

private func applyActiveView(_ active: ActiveView) {
    switch active {
    case .library:
        recommendationsHost.view.isHidden = true
        podcastsCollectionView.isHidden = false
        // Restore the library-specific nav bar items.
        updateNavigationButtons()
    case .recommendations:
        recommendationsHost.view.isHidden = false
        podcastsCollectionView.isHidden = true
        // Recommendations view does not use the library's right-side menu.
        navigationItem.rightBarButtonItems = nil
    }
}
```

- [ ] **Step 3: Restore library nav buttons on every `viewDidAppear`**

The existing `viewDidAppear` already calls `updateNavigationButtons()`. To keep the recommendations view from getting its menu back when returning to the tab while on the recommendations segment, wrap that call:

In `viewDidAppear(_ animated:)`, locate the line `updateNavigationButtons()` and replace it with:

```swift
applyActiveView(ActiveView(rawValue: switcher.selectedSegmentIndex) ?? .library)
```

(`applyActiveView` itself calls `updateNavigationButtons()` for the library case.)

- [ ] **Step 4: Build**

Expected: `** BUILD SUCCEEDED **`.

Watch for:
- `ThemeableView` API differences (`.style = .primaryUi01` may need a different setter; grep other usages).
- `UIHostingController<AnyView>` vs `ThemedHostingController`. If the project requires `ThemedHostingController` for theming to propagate, switch to that — pattern from `ManualEntriesViewController`.

- [ ] **Step 5: Format and commit**

```bash
make format
git add podcasts/PodcastListViewController.swift
git commit -m "wire Library/Recommendations switcher into Podcasts tab"
```

---

## Task 11: Smoke test on simulator

**Files:** none

- [ ] **Step 1: Boot a simulator and install**

```bash
xcrun simctl boot 7AB43694-2429-4444-BDC2-939523447581 2>/dev/null || true
open -a Simulator
./run.sh   # uses Conductor's run script; alternative: xcodebuild ... install
```

- [ ] **Step 2: Cold launch, no cache**

Delete `~/Library/Developer/CoreSimulator/Devices/<UUID>/data/Containers/Data/Application/<app-UUID>/Library/Caches/recommendations_*.json` (or reinstall the app) → Podcasts tab → tap "Recommendations" segment. Expect spinner, then list with sections.

- [ ] **Step 3: Verify all smoke-test scenarios**

Walk through each scenario from the spec:

1. Cold launch, no cache → spinner → list renders.
2. Sections visible 1 → 6 (or 7).
3. With Dreaming token + hours: sections at-or-below user level expanded.
4. Without Dreaming token (or cached hours = 0): all sections expanded.
5. Within Level 2: Chill Spanish Listening (107) sorts above ¡Cuéntame! (96) above Salsa! (21) above blank-mentions rows.
6. Mentions badge visible only when mentions > 0.
7. Subtitle = Region; blank region → no subtitle.
8. Tap "Dreaming Spanish" → search → match → opens podcast page.
9. Force-quit and reopen → tap "Dreaming Spanish" → no spinner, goes straight to page.
10. Tap ambiguous title → disambiguation sheet → tap a result → opens page.
11. From disambiguation: tap "Open external link" → Safari opens; subsequent taps go directly to Safari.
12. No-result + no-link row → "No matching podcast found" alert. Second tap within 30 days → same alert, no spinner.
13. Pull-to-refresh → spinner → list re-fetches.
14. Airplane mode + pull-to-refresh → list stays visible; failure surfaced (currently as `loadState` staying `.loaded`; no toast in v1 — acceptable).
15. Fresh install + airplane mode → error view with Retry; disable airplane mode → Retry → list loads.
16. Switch to Library, leave tab, return → still on Library. Switch to Recommendations, leave, return → still on Recommendations.
17. Library functionality unaffected (sort / layout / add).

- [ ] **Step 4: Capture any issues**

If any scenario fails, decide:
- Quick fix → make the fix, repeat the smoke test for the affected scenario.
- Out-of-scope behavior → file a follow-up note in the commit message; don't block the feature.

- [ ] **Step 5: Run all unit tests one more time**

```bash
xcodebuild -project podcasts.xcodeproj -scheme pocketcasts -configuration Debug \
  -destination 'platform=iOS Simulator,id=7AB43694-2429-4444-BDC2-939523447581' \
  -only-testing:PocketCastsTests/RecommendationsCSVParserTests \
  -only-testing:PocketCastsTests/RecommendationsSectionBuilderTests \
  -only-testing:PocketCastsTests/RecommendationFuzzyMatchTests \
  CODE_SIGNING_ALLOWED=NO test 2>&1 | tail -20
```

Expected: all green.

- [ ] **Step 6: Final commit (if any smoke-test fixes were made)**

```bash
git add -A
git commit -m "smoke test fixes for podcast recommendations"
```

---

## Self-review notes

- Spec coverage: every section of the spec maps to at least one task. Data model → T2. CSV parser → T3. Section parsing → T4. Repository (fetch/cache/resolve) → T6 (which depends on T5 fuzzy match). UI surface → T7-T9. PodcastListViewController wiring → T10. L10n → T1. Build/smoke verification → T11.
- TDD discipline applied for pure logic (CSV parser, section builder, fuzzy match). SwiftUI view layers are validated manually per project convention.
- pbxproj registration is described concretely in T2; subsequent tasks reference the same 4-step pattern with new ID pairs (`1B0B5B00` → `1B0B5B17`).
- The `RecommendationsView` task references `DreamingManager.shared.cachedTotalInputSeconds` — flagged as a verification step. If the symbol's actual name differs, the implementor should grep and substitute.
- `Theme.sharedTheme` is also flagged as a verification step in T10.
- Smoke-test step 14 acknowledges a minor v1 limitation (no toast on refresh-failure-with-cache); the spec accepted this as "transient toast or alert" but didn't mandate one. Implementing the toast is a follow-up.
