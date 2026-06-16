# Podcast recommendations — design

Date: 2026-06-15
Status: Draft

## Goal

Add a "Recommendations" view to the Podcasts tab that surfaces Spanish-learning content from the community-maintained [Refold Resource Doc](https://docs.google.com/spreadsheets/d/1lBmLxvWJpucXhRPayfXD7CVqpMoa2tyEbZi1rFAwsFs). Sections are grouped by hour-level (Level 1 → Level 6+), rows within a section are sorted by mention count (most-mentioned first). Tapping a row tries to open the podcast natively in Pocket Casts; if it can't be matched, the user is shown the top search results plus a fallback "Open external link" action. Matches are cached on disk so the tap-to-search cost is paid at most once per recommendation.

## Scope

### In scope

- New SwiftUI view `RecommendationsView` rendered inside the existing Podcasts tab.
- Segmented switcher under the nav bar in `PodcastListViewController` that toggles between **Library** (current UIKit content) and **Recommendations** (new SwiftUI host).
- Live fetch of the published CSV at app cold-start / pull-to-refresh; persistent CSV cache on disk so the view renders instantly on subsequent launches.
- Inline CSV parser (handles quoted fields with embedded commas).
- Section model derived from the `Level N - X Hours` divider rows in the sheet.
- Row layout: small artwork thumbnail (only after a Pocket Casts match is cached), title, region subtitle, trailing mentions badge.
- Sort: sections by level ascending (1 → 6+); rows within a section by `mentions` desc; rows with blank mentions sort to the bottom (tie-break alphabetical by title).
- User-level-aware initial section expansion based on `DreamingManager.cachedTotalInputSeconds`. Sections at or below the user's current level start expanded; sections above start collapsed. Graceful fallback to all-expanded if no Dreaming token / no cached total.
- Lazy on-tap match flow:
  - `PodcastSearchTask.search(term: title)` → fuzzy compare top result against the sheet title.
  - On match: cache the Pocket Casts UUID and route through `NavigationManager.navigate(to: .podcastPageKey, ...)`.
  - On miss: present a SwiftUI disambiguation sheet listing the top 5 results + "Open external link" row.
- Two on-disk caches (JSON files in `Caches/`):
  - `recommendations_csv.json` — the parsed sheet content + fetch timestamp.
  - `recommendations_matches.json` — `[sheetTitleNormalized: MatchResult]` where match is `.podcast(uuid)`, `.externalOnly(url)`, or `.miss(checkedAt)` with TTL 30 days for misses.
- Pull-to-refresh on the recommendations list (refetches CSV; does not invalidate match cache).
- Loading / error / empty states (see UX states section).

### Out of scope

- Editing or contributing back to the source spreadsheet.
- Downloading or auto-subscribing to matched podcasts.
- Per-row "I'm watching this" marker (could be a future feature; out of scope here).
- Filter or search bar on the recommendations view.
- Region / category filters (subtitle shows Region but isn't filterable in v1).
- Migrating the existing Library content into SwiftUI — the segmented switcher swaps which view is visible.
- Background refresh of matches; the match cache is permanent for hits (only misses expire).

## Data model

New file `podcasts/Recommendations/Recommendation.swift`:

```swift
import Foundation

/// One row in the Refold doc.
struct Recommendation: Identifiable, Codable, Equatable {
    let id: UUID                    // generated client-side for SwiftUI identity
    let title: String               // CSV col "Content"
    let location: String?           // CSV col "Location" (e.g. "YouTube", "Netflix")
    let mentions: Int               // CSV col "Mentions"; blank → 0
    let category: String?           // CSV col "Category"
    let region: String?             // CSV col "Region"
    let notes: String?              // CSV col "Notes"
    let otherLinks: String?         // CSV col "Other Links" (first URL preferred when opening)

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
    let level: Int                  // parsed from "Level N - X Hours"
    let title: String               // the full divider string, kept verbatim for display
    let hourThreshold: Int          // parsed X from "X Hours"
    var recommendations: [Recommendation]
}

/// Top-level snapshot stored on disk as recommendations_csv.json.
struct RecommendationsSnapshot: Codable, Equatable {
    let fetchedAt: Date
    let sections: [RecommendationSection]
}
```

### Match cache

New file `podcasts/Recommendations/RecommendationMatch.swift`:

```swift
import Foundation

enum RecommendationMatch: Codable, Equatable {
    case podcast(uuid: String)           // a Pocket Casts podcast UUID
    case externalOnly(url: String)       // user picked "Open external link" — sticky
    case miss(checkedAt: Date)           // we searched and didn't find a usable result
}
```

Persisted as `[matchKey: RecommendationMatch]` in `recommendations_matches.json`. Miss entries are honored for 30 days then re-searched on next tap.

## CSV parser

Inline in `RecommendationsCSVParser.swift`, ~25 lines. Handles:
- Quoted fields containing commas (`"a, b",c` → `["a, b", "c"]`).
- Doubled quotes inside quoted fields (`"He said ""hi"""` → `He said "hi"`).
- Embedded newlines inside quoted fields.
- Trailing empty trailing columns (the doc has 6 trailing empty columns).

Pseudocode:

```swift
enum RecommendationsCSVParser {
    static func rows(from text: String) -> [[String]] {
        var rows: [[String]] = []
        var current: [String] = []
        var field = ""
        var inQuotes = false
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            switch (c, inQuotes) {
            case ("\"", true) where text.index(after: i) < text.endIndex && text[text.index(after: i)] == "\"":
                field.append("\"")
                i = text.index(after: i)         // skip second quote
            case ("\"", _):
                inQuotes.toggle()
            case (",", false):
                current.append(field); field = ""
            case ("\n", false), ("\r\n", false):
                current.append(field); rows.append(current)
                current = []; field = ""
            default:
                field.append(c)
            }
            i = text.index(after: i)
        }
        if !field.isEmpty || !current.isEmpty {
            current.append(field); rows.append(current)
        }
        return rows
    }
}
```

(Final implementation handles `\r\n` via a small lookahead. See the [executing-plans] step for the exact code.)

## Section parsing

After CSV rows are parsed, walk them top-to-bottom:

1. Skip header row (`Content,Location,Mentions,...`).
2. Skip the two preamble explanation rows.
3. Skip the `Refold Resource Doc` title row.
4. When a row's first column matches the regex `^Level\s+(\d+)\s*-\s*(\d+)\s*Hours?$`, start a new `RecommendationSection`.
5. Otherwise, if the current section is non-nil and `Content` (col 0) is non-empty, append a `Recommendation`.
6. Once all rows are consumed: within each section, sort `recommendations`:
   - Primary: `mentions` descending.
   - Secondary (blank mentions, i.e. value 0): always at the bottom of the section.
   - Tertiary tie-break: title ascending (case-insensitive).
7. Sort sections by `level` ascending.

## Data source — fetch + cache

New file `podcasts/Recommendations/RecommendationsRepository.swift`. Singleton (`shared`), `@MainActor`.

```swift
@MainActor
final class RecommendationsRepository: ObservableObject {
    static let shared = RecommendationsRepository()

    @Published private(set) var snapshot: RecommendationsSnapshot?
    @Published private(set) var matches: [String: RecommendationMatch] = [:]
    @Published private(set) var loadState: LoadState = .idle

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(message: String)
    }

    func loadOnAppear() async  // reads cache, then fetches in background if cache is stale or absent
    func refresh() async       // pull-to-refresh — force-fetch, surface errors
    func resolve(for rec: Recommendation) async -> RecommendationResolution
    func overrideMatch(_ match: RecommendationMatch, for rec: Recommendation)
    private func loadCachesFromDisk()
    private func persistSnapshot(_ snapshot: RecommendationsSnapshot)
    private func persistMatches()
}
```

### `loadOnAppear`

1. If `snapshot == nil`, read `recommendations_csv.json` from `Caches/`. If found, set `snapshot` immediately and `loadState = .loaded`.
2. If snapshot is missing OR `fetchedAt` is > 1 hour ago, kick off a background fetch.
3. While background-fetching with a cached snapshot in hand, do **not** change `loadState` away from `.loaded` — the cached data stays visible silently. Errors are swallowed (a stale snapshot is fine until next refresh).
4. With no cache and a fetch in flight: `loadState = .loading`.
5. With no cache and a fetch that fails: `loadState = .failed(message:)`.

### `refresh`

Always re-fetches. On success: replace snapshot + persist. On failure with cached snapshot: keep the cached one visible and surface the error transiently (toast or alert — see UX section). On failure without cache: `loadState = .failed`.

### File locations

```swift
private var cachesDir: URL {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
}
private var snapshotFile: URL { cachesDir.appendingPathComponent("recommendations_csv.json") }
private var matchesFile: URL  { cachesDir.appendingPathComponent("recommendations_matches.json") }
```

The system can evict `Caches/` under storage pressure. That's acceptable — on next launch we just re-fetch and re-search.

### Fetch

```swift
private let csvURL = URL(string:
    "https://docs.google.com/spreadsheets/d/1lBmLxvWJpucXhRPayfXD7CVqpMoa2tyEbZi1rFAwsFs/export?format=csv&gid=0"
)!

private func fetchCSV() async throws -> RecommendationsSnapshot {
    let (data, response) = try await URLSession.shared.data(from: csvURL)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
          let text = String(data: data, encoding: .utf8) else {
        throw RecommendationsError.fetchFailed
    }
    let rows = RecommendationsCSVParser.rows(from: text)
    let sections = RecommendationsSectionBuilder.build(from: rows)
    return RecommendationsSnapshot(fetchedAt: Date(), sections: sections)
}
```

## Matching to Pocket Casts

The repository exposes `resolve(for:)` which returns a discriminated outcome the caller can act on directly. This is different from the cached `RecommendationMatch` enum (which only stores terminal states): `resolve` may return a transient outcome that carries the search results needed to populate the disambiguation sheet.

```swift
/// Outcome of resolving a recommendation tap. Drives the row-tap flow.
/// Not persisted — the cache stores `RecommendationMatch` (terminal states only).
enum RecommendationResolution {
    /// We have (or just found) a confident Pocket Casts match.
    case podcast(uuid: String)
    /// User previously chose "Open external link" for this row.
    case externalOnly(url: String)
    /// Search yielded results but none fuzzy-matched. Caller should open the
    /// disambiguation sheet with these results plus an "Open external link"
    /// row when `externalURL` is non-nil.
    case needsDisambiguation(results: [PodcastFolderSearchResult], externalURL: URL?)
    /// Search yielded zero usable results AND there's no external link.
    /// Caller should show the "No matching podcast found" alert.
    case noOptions
}

func resolve(for rec: Recommendation) async -> RecommendationResolution {
    // 1. Cache hit on a terminal state — return directly.
    if let cached = matches[rec.matchKey] {
        switch cached {
        case .podcast(let uuid):
            return .podcast(uuid: uuid)
        case .externalOnly(let url):
            return .externalOnly(url: url)
        case .miss(let checkedAt) where Date().timeIntervalSince(checkedAt) <= 30 * 86400:
            // Honor cached miss within TTL — show disambiguation/no-options
            // using only the external link (no re-search).
            return externalURL(for: rec).map { .needsDisambiguation(results: [], externalURL: $0) }
                ?? .noOptions
        case .miss:
            break // expired; fall through to re-search
        }
    }

    // 2. Search Pocket Casts.
    let results: [PodcastFolderSearchResult]
    do {
        results = try await PodcastSearchTask().search(term: rec.title)
    } catch {
        // Network/search failed. Don't persist — try again next tap.
        return externalURL(for: rec).map { .needsDisambiguation(results: [], externalURL: $0) }
            ?? .noOptions
    }

    // 3. Try fuzzy match on the top result.
    if let top = results.first, fuzzyMatch(rec.title, top.title) {
        matches[rec.matchKey] = .podcast(uuid: top.uuid)
        persistMatches()
        return .podcast(uuid: top.uuid)
    }

    // 4. No confident match. Decide what to surface.
    let extURL = externalURL(for: rec)
    if results.isEmpty && extURL == nil {
        // Persist as a miss so we don't re-search every tap for 30 days.
        matches[rec.matchKey] = .miss(checkedAt: Date())
        persistMatches()
        return .noOptions
    }
    // Don't persist — user may still pick a result, which becomes a hit.
    return .needsDisambiguation(results: results, externalURL: extURL)
}

private func externalURL(for rec: Recommendation) -> URL? {
    guard let raw = rec.otherLinks?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
    // The "Other Links" column may contain multiple whitespace/comma-separated URLs.
    // Use the first parseable one.
    let candidates = raw.components(separatedBy: CharacterSet(charactersIn: " ,\n"))
    return candidates.lazy.compactMap { URL(string: $0) }.first
}
```

When the disambiguation sheet returns a user selection, the caller invokes `overrideMatch(_:for:)` to persist `.podcast(uuid:)` or `.externalOnly(url:)`. Subsequent taps short-circuit on the cache.

### Fuzzy match

Two-step:
1. Normalize both strings (lowercase, strip diacritics, collapse whitespace, drop punctuation).
2. Accept if normalized strings are equal OR if Jaro-Winkler similarity ≥ 0.92. Implement Jaro-Winkler inline (~40 lines). If Jaro-Winkler is too noisy in practice, fall back to "normalized prefix match where the shorter is a prefix of the longer of length ≥ 6".

The implementation step can prefer the simpler "normalized equality OR shorter is prefix of longer" check first and only add Jaro-Winkler if smoke testing reveals too many false negatives.

## Disambiguation sheet

`RecommendationDisambiguationView.swift`. SwiftUI sheet presented when `resolve(for:)` returns `.needsDisambiguation(results:externalURL:)`. Receives the source `Recommendation`, the `results: [PodcastFolderSearchResult]` (may be empty), and an optional `externalURL: URL`.

Layout:

```
Nav bar:  [Cancel]   Choose podcast
─────────────────────────────────────
"<sheet title>"                        ← header (the Recommendation.title)
─────────────────────────────────────
[artwork] Result 1 Title
          Result 1 Author
[artwork] Result 2 Title
          Result 2 Author
…                                       ← top 5 results, omitted if results.isEmpty
─────────────────────────────────────
Open external link →                    ← only shown when externalURL != nil
```

By construction, the sheet is never presented with both `results.isEmpty` AND `externalURL == nil` — `resolve(for:)` returns `.noOptions` in that case so the caller shows the alert instead. So the sheet always has at least one tappable row.

- Tapping a result: calls `repository.overrideMatch(.podcast(uuid:), for: rec)`, dismisses the sheet, routes to the podcast page via `NavigationManager.navigate(to: .podcastPageKey, ...)`.
- Tapping "Open external link": calls `repository.overrideMatch(.externalOnly(url:), for: rec)`, dismisses, opens the URL in Safari via `UIApplication.shared.open(...)`. The next tap on that row short-circuits to the link.
- Tapping Cancel: dismisses without persisting anything. Next tap re-runs the search.

## Row tap flow

```
User taps row
  ↓
repository.resolve(for: rec)
  ├─ .podcast(uuid)                       → NavigationManager → podcast page
  ├─ .externalOnly(url)                   → Safari (UIApplication.open)
  ├─ .needsDisambiguation(results, url?)  → present DisambiguationView
  │                                         (results may be empty; "Open external
  │                                          link" row visible iff url != nil)
  └─ .noOptions                           → alert "No matching podcast found"
```

The view's `handleTap(rec)` looks like:

```swift
private func handleTap(_ rec: Recommendation) {
    Task {
        let outcome = await repo.resolve(for: rec)
        switch outcome {
        case .podcast(let uuid):
            NavigationManager.sharedManager.navigateTo(
                NavigationManager.podcastPageKey,
                data: [NavigationManager.podcastKey: uuid]
            )
        case .externalOnly(let url):
            UIApplication.shared.open(url)
        case .needsDisambiguation(let results, let externalURL):
            disambiguationPayload = .init(rec: rec, results: results, externalURL: externalURL)
        case .noOptions:
            showNoMatchAlert = true
        }
    }
}
```

## UI — `RecommendationsView`

```swift
struct RecommendationsView: View {
    @EnvironmentObject var theme: Theme
    @StateObject private var repo = RecommendationsRepository.shared
    @State private var expandedSections: Set<Int> = []   // levels currently expanded

    var body: some View {
        ZStack {
            theme.primaryUi01.ignoresSafeArea()
            content
        }
        .task { await repo.loadOnAppear(); initializeExpansion() }
        .refreshable { await repo.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        switch repo.loadState {
        case .idle, .loading:
            ProgressView().tint(theme.primaryInteractive01)
        case .failed(let msg):
            errorView(msg)
        case .loaded:
            list
        }
    }

    private var list: some View {
        List {
            ForEach(repo.snapshot?.sections ?? []) { section in
                Section(header: sectionHeader(section, isExpanded: expandedSections.contains(section.level))) {
                    if expandedSections.contains(section.level) {
                        ForEach(section.recommendations) { rec in
                            RecommendationRow(rec: rec)
                                .listRowBackground(theme.primaryUi02)
                                .onTapGesture { handleTap(rec) }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
}
```

### Section header

Tappable row that toggles the section's level in `expandedSections`. Layout:

```
Level 2 - 50 Hours              [chevron.right rotated 90° if expanded]
```

Styled to match the app's section headers (use `theme.primaryText02` for the title, `theme.primaryText01` for the chevron, `theme.primaryUi02` background).

### Row layout — `RecommendationRow`

```
[artwork 44×44] Chill Spanish Listening     [107]
                Latin America
```

- Artwork: rounded 8pt corners. When `match == .podcast(uuid)`: load via `ImageManager.shared.podcastUrl(imageSize: .grid, uuid: uuid)` rendered through `AsyncImage` or a SwiftUI wrapper. Otherwise: placeholder (`theme.primaryUi02` square with `mic.fill` glyph in `theme.primaryText02`).
- Title: `theme.primaryText01`, `.body`, single line, truncation tail.
- Subtitle: Region (`theme.primaryText02`, `.caption`). Hidden when region is blank.
- Mentions badge: trailing capsule, `theme.primaryUi02` background, `theme.primaryText01` text, `.caption.weight(.semibold)`. Shown only when `mentions > 0`.

The row pre-resolves its match on appear (`task`) so cached artwork can render without a tap. The resolver is non-blocking — placeholder shows until match comes back.

### Section expansion init

```swift
private func initializeExpansion() {
    guard expandedSections.isEmpty, let sections = repo.snapshot?.sections else { return }
    let totalHours = DreamingManager.shared.cachedTotalInputSeconds / 3600
    let userLevel = sections
        .filter { Double($0.hourThreshold) <= totalHours }
        .map(\.level)
        .max() ?? 1
    expandedSections = Set(sections.filter { $0.level <= userLevel }.map(\.level))
    if expandedSections.isEmpty {
        // No Dreaming data → fall back to all-expanded.
        expandedSections = Set(sections.map(\.level))
    }
}
```

Scroll-to-user-level: after initial layout, if `userLevel > 1`, use `ScrollViewReader` to scroll to the user's section header. Implementation step can choose to defer this to a follow-up if `ScrollViewReader` + `List` proves finicky.

### Empty / loading / error states

| State | UI |
|-------|----|
| First load, no cache, fetch in flight | Centered `ProgressView()`. |
| Cache present, background fetch in flight | Show list immediately; fetch is silent. |
| Cache present, refresh failed | Show list; surface error via brief alert. |
| No cache, fetch failed | Centered error view with message + `Retry` button. |
| Loaded, zero sections (shouldn't happen but defensive) | Centered "No recommendations available" text. |

### Pull-to-refresh

Native `.refreshable { await repo.refresh() }`. Standard system spinner; no custom UI.

## Wiring into the Podcasts tab

`PodcastListViewController` already manages the Library content. The switcher and both child views all live inside `PodcastListViewController` — the switcher is a UIKit element that toggles which child is visible.

### Layout

```
┌─────────────────────────────────┐
│  UINavigationBar  (system)      │
├─────────────────────────────────┤
│  switcherContainer (UIView)     │  ← pinned, height 44pt
│  [ Library  |  Recommendations ]│     does NOT scroll with content
├─────────────────────────────────┤
│  child content area             │  ← exactly one of:
│  • existing library subviews    │     - the current Library content
│  • UIHostingController.view     │     - the RecommendationsView host
└─────────────────────────────────┘
```

### Changes to `PodcastListViewController.swift`

- Add a `switcherContainer: UIView` pinned to the top of `view` with Auto Layout (top to safe area, leading/trailing to superview, height 44pt). It is **not** placed in the nav bar's `titleView`; it lives below the nav bar in the controller's own view hierarchy and does not scroll.
- Inside `switcherContainer`, add a `UISegmentedControl` (`.segmented` style — system default) with two segments: `L10n.podcastsLibrary` ("Library") and `L10n.podcastsRecommendations` ("Recommendations"). Centered horizontally, 8pt vertical padding.
- The existing library subviews' top constraints shift from `safe area top` to `switcherContainer.bottomAnchor`.
- Add a child controller `recommendationsHost: UIHostingController<RecommendationsView>`. Its `view.topAnchor` also pins to `switcherContainer.bottomAnchor`; leading/trailing/bottom pin to the same edges the library uses today.
- On segment change:
  - `0` → `recommendationsHost.view.isHidden = true`; library subviews `isHidden = false`.
  - `1` → `recommendationsHost.view.isHidden = false`; library subviews `isHidden = true`.
- The segmented control's selected index persists to UserDefaults under key `"PodcastsTabActiveView"`. On `viewDidLoad`, read the key and apply the matching segment before first display.
- The existing nav-bar right-side menu (more / sort / change layout) is **only relevant to the Library view** — when the user is on Recommendations, set the right `UIBarButtonItem` to `nil`. Pull-to-refresh on the recommendations list is the only refresh mechanism we need there.

### New L10n keys

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
```

## File-level change summary

- `podcasts/Recommendations/Recommendation.swift` — **new file** (`Recommendation`, `RecommendationSection`, `RecommendationsSnapshot`).
- `podcasts/Recommendations/RecommendationMatch.swift` — **new file** (enum + JSON codable).
- `podcasts/Recommendations/RecommendationsCSVParser.swift` — **new file** (inline CSV parser).
- `podcasts/Recommendations/RecommendationsSectionBuilder.swift` — **new file** (rows → sections).
- `podcasts/Recommendations/RecommendationsRepository.swift` — **new file** (singleton, fetch + cache + match).
- `podcasts/Recommendations/RecommendationsView.swift` — **new file** (SwiftUI list view).
- `podcasts/Recommendations/RecommendationRow.swift` — **new file** (single row layout).
- `podcasts/Recommendations/RecommendationDisambiguationView.swift` — **new file** (SwiftUI sheet for non-fuzzy matches).
- `podcasts/PodcastListViewController.swift` — add segmented switcher, embed `UIHostingController`, persist active segment, hide library-only nav menu when on Recommendations.
- `podcasts/en.lproj/Localizable.strings` — add 7 keys above.
- `podcasts/Strings+Generated.swift` — regenerated by build phase.
- `podcasts.xcodeproj/project.pbxproj` — register each new file (PBXBuildFile, PBXFileReference, group entry, Sources phase entry).

## Verification

### Build check

```
xcodebuild -project podcasts.xcodeproj -scheme pocketcasts -configuration Debug \
  -destination 'platform=iOS Simulator,id=7AB43694-2429-4444-BDC2-939523447581' \
  CODE_SIGNING_ALLOWED=NO build
```

Ends with `** BUILD SUCCEEDED **`.

### Smoke test

1. **Cold launch, no cache:** Podcasts tab → tap "Recommendations" segment → spinner → list renders with sections.
2. **Sections visible by level:** Level 1 → Level 6 (or 7 if the sheet has it). User-level-aware expansion: with a Dreaming token + cached hours, sections at-or-below user level are expanded.
3. **No Dreaming token / no cached hours:** all sections expanded by default.
4. **Sort:** Within Level 2, Chill Spanish Listening (107) sorts above ¡Cuéntame! (96) sorts above Salsa! (21) sorts above blank-mentions rows.
5. **Badge:** Rows with `mentions > 0` show the trailing capsule. Rows with no mentions show no badge.
6. **Subtitle:** Region column populates the subtitle. Blank region → no subtitle line.
7. **Match → podcast page:** Tap "Dreaming Spanish" → search → match → opens podcast page in Pocket Casts.
8. **Persistent match cache:** Force-quit, reopen → tap same row → goes straight to podcast page (no search spinner).
9. **Match → disambiguation:** Tap a row with ambiguous title → search results sheet appears → tap a result → opens podcast page; next tap on same row goes directly there.
10. **External-only fallback:** From disambiguation sheet, tap "Open external link" → Safari opens. Subsequent taps on that row go to Safari directly.
11. **No match + no external link:** Tap a row with no Pocket Casts results and blank Other Links → alert "No matching podcast found." (Second tap on the same row, within 30 days, surfaces the same alert without a search spinner — the miss is cached.)
11a. **No match + has external link:** Tap a row with no Pocket Casts results but populated Other Links → disambiguation sheet shows only the "Open external link" row → tap it → Safari opens.
12. **Pull-to-refresh:** Pull down → spinner → CSV re-fetched; new content visible if sheet changed.
13. **Refresh failure with cache:** Toggle airplane mode → pull-to-refresh → alert "Couldn't load recommendations…"; existing list stays visible.
14. **Refresh failure no cache:** Fresh install + airplane mode → recommendations tab → error view with Retry button. Disable airplane mode → tap Retry → list loads.
15. **Switcher persistence:** Switch to Recommendations → leave the tab → return → still on Recommendations. Same for Library.
16. **Library still works:** Switch to Library → all existing functionality intact (sort / layout / add / etc.).
