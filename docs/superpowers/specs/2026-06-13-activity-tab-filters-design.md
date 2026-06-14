# Activity tab filters — design

Date: 2026-06-13
Status: Approved

## Goal

Broaden the current "Manual Entries" tab to show every Dreaming Spanish `externalTime` entry (not just talking sessions), let the user filter by entry category via a chip row, and rename the tab to "Activity". Lock in a forward-looking description format so the next PR (new entry forms for Watching / sub-typed Talking) and a later PR (charts) have a clear target.

## Scope

### In scope

- Rename tab → "Activity".
- Show every entry returned by `DreamingManager.fetchExternalTimes`.
- Horizontal chip row at the top of the view with five chips: **All**, **Podcasts**, **Talking**, **Watching**, **Initial**.
- "All" is the default; selection does not persist across app launches.
- Chip row sits above the entry list and stays visible while the list scrolls.
- Category-aware empty state ("No watching entries yet" / "No entries yet" for All).
- Tab bar icon swap: `mic.fill` → `list.bullet`.
- Add `L10n.activity` string (added to `Localizable.strings`; `Strings+Generated.swift` regenerates via the existing L10n build phase).
- Document the forward-looking description format for future entries (this PR adds the documentation; no code in this PR depends on it).

### Out of scope (deferred)

- New entry forms for Watching (YouTube / TV) and Talking sub-types (Talking / Crosstalk / Reverse Crosstalk).
- Charts that parse description strings for per-creator / per-series breakdowns.
- Date-range filters, search, or persisted filter state.
- Retroactive rewriting of existing talk entries (`"Crosstalk Session"`, `"Output Session"`).

## Background

`DreamingManager.fetchExternalTimes` returns `[ExternalTimeEntry]` where each entry has `id`, `type`, `date` (yyyy-MM-dd), `timeSeconds`, `description`. The Dreaming Spanish API supports more `type` values than this fork currently uses:

- `initial` — lifetime kickoff hours (one-time entry per user).
- `listening` — audio; our podcast auto-logger already sends this.
- `watching` — video; we never send this, but the API accepts it and `DreamingStatsView` already renders it.
- `talking` — speaking practice; our talk-session form sends this.

Categorization is therefore already free on the `type` field — no description-prefix scheme is needed for the primary category. Description-level sub-categorization is only needed for future creator/series charts.

## Category model

A new private enum in `ManualEntriesView.swift`:

```swift
enum EntryCategory: String, CaseIterable, Identifiable {
    case all
    case podcasts    // DS type "listening"
    case talking     // DS type "talking"
    case watching    // DS type "watching"
    case initial     // DS type "initial"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All"
        case .podcasts: return "Podcasts"
        case .talking: return "Talking"
        case .watching: return "Watching"
        case .initial: return "Initial"
        }
    }

    /// The Dreaming Spanish `type` field this category matches.
    /// `nil` for `.all` (no filter applied).
    var apiType: String? {
        switch self {
        case .all: return nil
        case .podcasts: return "listening"
        case .talking: return "talking"
        case .watching: return "watching"
        case .initial: return "initial"
        }
    }
}
```

Notes:

- `CaseIterable` order = chip render order (All first, Initial last).
- Display names diverge from raw `type` values deliberately ("Podcasts" beats "Listening" in this UI).
- No per-category colors on the enum; chip colors come from the theme.

## Filter UI

### Layout

`VStack` structure:

```
VStack(spacing: 0) {
    chipRow          // always visible
    ScrollView {     // entry list scrolls underneath
        LazyVStack { ... }
    }
}
```

The chip row sits above the ScrollView in the VStack — always visible while the list scrolls. Implementation note: not literally a pinned section header; just structurally above the scrollable region.

### Chip row

- Horizontal `ScrollView(.horizontal, showsIndicators: false)` containing a `HStack(spacing: 8)` of chips.
- Outer padding: `.horizontal, 16` and `.vertical, 8`.
- Row background: `theme.primaryUi01` (same as page; chips appear to float).
- One chip per `EntryCategory` case, in `CaseIterable` order.

### Chip styling

- `Capsule()` button.
- Inner padding: vertical 8, horizontal 14.
- Font: `.subheadline.weight(.semibold)`.
- Selected: `background = theme.primaryInteractive01`, `foreground = theme.primaryUi01`.
- Unselected: `background = theme.primaryUi02`, `foreground = theme.primaryText01`.
- Tap action: sets `selectedCategory = category`.

### Selection state

- `@State private var selectedCategory: EntryCategory = .all`.
- Does not persist; resets to `.all` on each view appearance.

### Empty state

When the filtered list is empty, the existing empty-state placeholder shows but the message is category-aware:

- `.all` → "No entries yet"
- any other → `"No \(selectedCategory.displayName.lowercased()) entries yet"`

Subtitle stays "Tap + in the top right to log a session".

## Filtering logic

```swift
private func filterAndSort(_ entries: [DreamingManager.ExternalTimeEntry]) -> [DreamingManager.ExternalTimeEntry] {
    entries
        .filter { matchesSelectedCategory($0) }
        .sorted { $0.date > $1.date }
}

private func matchesSelectedCategory(_ entry: DreamingManager.ExternalTimeEntry) -> Bool {
    guard let apiType = selectedCategory.apiType else { return true } // .all
    return entry.type == apiType
}
```

Notes:

- The existing `isManualEntry(_:)` function gets **deleted**.
- Filtering runs on every render (computed property). Entry counts are small (a few hundred at most); no debounce or memoization needed.
- Unknown future `type` values from the API (e.g. a hypothetical `reading`) match only `.all`. Users still see them; just no dedicated chip. This is the desired fail-safe.

## Tab rename

- `ManualEntriesViewController.title = L10n.activity` (was `"Manual Entries"`).
- `MainTabBarController.swift`: `talkViewController.tabBarItem = UITabBarItem(title: L10n.activity, image: UIImage(systemName: "list.bullet"), tag: ...)`.
- `L10n.activity` added via `podcasts/en.lproj/Localizable.strings` — the L10n build phase regenerates `Strings+Generated.swift`.
- The internal `pcTabs` enum case is `.talk`; leaving it as-is since renaming the enum case would ripple through navigation code unnecessarily.

## Forward-looking description format (documented, not implemented)

The next PR (new entry forms) will write entries with these description formats. This PR documents them so the entry-form work and the eventual chart-parsing work share a single source of truth.

| Future entry kind | DS `type` | Description format |
|---|---|---|
| Watching: YouTube | `watching` | `"<Creator> \| <Video Title>"` |
| Watching: TV / Movies | `watching` | `"<Series> \| <Episode>"` |
| Talking | `talking` | `"Talking"` or `"Talking \| <user description>"` |
| Crosstalk | `talking` | `"Crosstalk"` or `"Crosstalk \| <user description>"` |
| Reverse Crosstalk | `talking` | `"Reverse Crosstalk"` or `"Reverse Crosstalk \| <user description>"` |
| Podcasts (legacy) | `listening` | `"<Podcast> - Ep <N>"` or `"<Podcast> - Eps <ranges>"` |

Uniform parser for new-format entries:

```
split(" | ", limit: 2)
  length 2 → group = trim(first), specific = trim(second)
  length 1 → group = whole, specific = nil
```

Podcasts use a different delimiter (`" - Ep"` / `" - Eps"`); their parser is a separate code path and is not unified.

### Legacy talking entries

Historical entries from this app use `"Crosstalk Session"` and `"Output Session"` (the current `L10n.talkCrosstalkSession` / `L10n.talkOutputSession`). When charts ship:

- `"Crosstalk Session"` → group = "Crosstalk Session" (chart code can normalize to "Crosstalk" via a contains-check).
- `"Output Session"` → no "Output" sub-type in the new scheme; the entry-form PR will decide whether to map this to "Talking" or leave it as a legacy "Output" bucket in charts.

## Verification

No unit tests (no existing pattern for view-level tests in this codebase's Dreaming code). Manual verification on simulator:

1. `xcodebuild ... build` passes.
2. Tab bar shows "Activity" with the `list.bullet` icon.
3. With "All" selected, every entry type (initial, listening, talking, watching if any exist) appears in the list.
4. Tapping each chip narrows the list to entries of that `type` only.
5. Empty category shows the category-aware empty message.
6. Adding a talk session via the existing Timer / + flow refreshes the list and the new entry appears under "All" and "Talking".

## File-level change summary

- `podcasts/Dreaming/ManualEntriesView.swift`
  - Add `EntryCategory` enum.
  - Add `@State selectedCategory`.
  - Add chip-row builder + `categoryChip(...)` helper.
  - Restructure body into `VStack { chipRow; ScrollView }`.
  - Replace `isManualEntry(_:)` with `matchesSelectedCategory(_:)`.
  - Update `ManualEntriesViewController.title` to `L10n.activity`.
  - Empty-state message now depends on `selectedCategory`.
- `podcasts/MainTabBarController.swift`
  - Tab bar item: title → `L10n.activity`, image → `UIImage(systemName: "list.bullet")`.
- `podcasts/en.lproj/Localizable.strings`
  - Add `"activity" = "Activity";`.
- `podcasts/Strings+Generated.swift`
  - Regenerated by the L10n build phase (no manual edit expected).
- `docs/superpowers/specs/2026-06-13-activity-tab-filters-design.md` (this file).
