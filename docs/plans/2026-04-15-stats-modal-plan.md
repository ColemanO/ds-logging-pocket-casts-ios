# Stats Modal Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move charts to a dedicated SwiftUI stats modal with a shared date range selector, triggered by a "View Stats" button on the total/level card.

**Architecture:** New `DreamingStatsView` (SwiftUI) owns the date range state and filters data for all three charts. The `DateRange` enum and filtering logic move from `DreamingProgressChartView` up to the stats view. The progress chart view drops its internal date range bar and accepts pre-filtered data. The breakdown builders move from the view controller to the stats view. The view controller removes chart cards and adds a button to present the modal.

**Tech Stack:** SwiftUI, Swift Charts, UIKit (modal presentation via UIHostingController)

---

### Task 1: Refactor DreamingProgressChartView to accept filtered data

The progress chart currently manages its own date range selector and filters data internally. We need to remove that so the parent stats view can control filtering.

**Files:**
- Modify: `podcasts/Dreaming/DreamingProgressChartView.swift`

**Changes:**

1. Remove the `DateRange` enum (it will live in the stats view)
2. Remove `@State private var selectedRange`
3. Remove the `dateRangeBar` property and its call in `body`
4. Remove `dateRangeInterval`, `filteredPoints`, `filteredThresholds` computed properties
5. Remove `dropdownMenu`, `isMonthSelected`, `rangeMenuLabel`, `monthMenuLabel`, `availableMonths`, `monthLabel` helpers
6. Remove `presetRanges`
7. Change all references from `filteredPoints` to `dataPoints` (the parent will pre-filter)
8. Change `filteredThresholds` references to use a new computed property that works directly on `dataPoints`:

```swift
private var visibleThresholds: [(level: Int, hours: Double)] {
    guard let minHours = dataPoints.first?.cumulativeHours,
          let maxHours = dataPoints.last?.cumulativeHours else { return [] }
    let ceiling = maxHours + (maxHours - minHours) * 0.15
    return levelThresholds.filter { $0.hours > 0 && $0.hours >= minHours && $0.hours <= ceiling }
}
```

9. In `statsBar`, change references from `filteredPoints` to `dataPoints`
10. In `periodTotalHours`, it references `dataPoints` (the full dataset) to calculate deltas — this needs updating since the parent now filters. Change the `dataPoints` parameter name to `allDataPoints` and add a new `filteredDataPoints` that the chart receives:

Actually, simpler approach: The chart should just receive the filtered data as `dataPoints` and `allDataPoints` for the period calculation:

```swift
struct DreamingProgressChartView: View {
    let dataPoints: [DataPoint]       // filtered to selected range
    let allDataPoints: [DataPoint]    // full unfiltered dataset (for period total calculation)
    let levelThresholds: [(level: Int, hours: Double)]
```

Update `periodTotalHours` to use `allDataPoints` where it currently references `dataPoints` for lookups.

**Step 1:** Make all the changes listed above
**Step 2:** Verify build: `make build`

---

### Task 2: Create DreamingStatsView

**Files:**
- Create: `podcasts/Dreaming/DreamingStatsView.swift`

This is the main SwiftUI view presented as a modal sheet. It owns the date range state and filters all chart data.

**Structure:**

```swift
import Charts
import SwiftUI

@available(iOS 16.0, *)
struct DreamingStatsView: View {
    @Environment(\.dismiss) private var dismiss

    // DateRange enum (moved from DreamingProgressChartView)
    enum DateRange: Hashable {
        case month(Date)
        case past1W, mtd, past1M, ytd, past1Y, all
    }

    @State private var selectedRange: DateRange = .all

    // Data from DreamingManager (passed in at init or loaded on appear)
    let chartDataPoints: [DreamingProgressChartView.DataPoint]
    let levelThresholds: [(level: Int, hours: Double)]
    let externalTimes: [DreamingManager.ExternalTimeEntry]
    let platformWatchTimeSeconds: Double

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    dateRangeSelector
                    progressChart
                    if #available(iOS 17.0, *) {
                        inputBreakdownChart
                        podcastBreakdownChart
                    }
                }
                .padding(.horizontal, 16)
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
```

**Date range selector:** Reuse the same dropdown menu pattern — two `Menu` dropdowns (preset ranges + month picker), left-aligned in an HStack. Same `presetRanges` list and `dropdownMenu` helper as the old chart view had.

**Date filtering:** Same `dateRangeInterval` computed property. Apply it to:
- `filteredChartPoints` — filters `chartDataPoints` by date
- `filteredExternalTimes` — filters `externalTimes` by date (parse the date string to compare)

**Progress chart section:**
```swift
private var progressChart: some View {
    DreamingProgressChartView(
        dataPoints: filteredChartPoints,
        allDataPoints: chartDataPoints,
        levelThresholds: levelThresholds
    )
}
```

**Input breakdown section** (iOS 17+): Build slices from `filteredExternalTimes` using same logic as the existing `buildBreakdownSlices()` in the view controller — group by type (initial, listening, watching, talking) plus `platformWatchTimeSeconds` (note: platform time is all-time only and can't be filtered by date, so for non-"all" ranges, only show external time categories).

For the "all" range, include platform hours as "Dreaming Spanish". For filtered ranges, the platform time isn't date-filterable, so omit it and only show external time entries.

**Podcast breakdown section** (iOS 17+): Build slices from `filteredExternalTimes.filter { $0.type == "listening" }` using same logic as existing `buildPodcastBreakdownSlices()` — regex strip ep suffix, case-insensitive grouping, 1% threshold for "Other".

**Step 1:** Create the file with all the above
**Step 2:** Verify build: `make build`

---

### Task 3: Modify DreamingProgressViewController

**Files:**
- Modify: `podcasts/Dreaming/DreamingProgressViewController.swift`

**Changes:**

1. **Remove chart card properties** (lines 37-47):
   - Remove `chartCard`, `chartHostingController`
   - Remove `breakdownCard`, `breakdownHostingController`
   - Remove `podcastBreakdownCard`, `podcastBreakdownHostingController`

2. **Add a "View Stats" button** to `totalLevelCard`:
   - Add `private let viewStatsButton = UIButton(type: .system)` property
   - In `setupTotalLevelCard()`, configure the button:
     ```swift
     viewStatsButton.setTitle("View Stats", for: .normal)
     viewStatsButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .medium)
     viewStatsButton.addTarget(self, action: #selector(showStats), for: .touchUpInside)
     viewStatsButton.translatesAutoresizingMaskIntoConstraints = false
     totalLevelCard.addSubview(viewStatsButton)
     ```
   - Update constraints: change `levelLabel.bottomAnchor` to connect to `viewStatsButton.topAnchor` instead of `totalLevelCard.bottomAnchor`. Add:
     ```swift
     viewStatsButton.topAnchor.constraint(equalTo: levelLabel.bottomAnchor, constant: 16),
     viewStatsButton.centerXAnchor.constraint(equalTo: totalLevelCard.centerXAnchor),
     viewStatsButton.bottomAnchor.constraint(equalTo: totalLevelCard.bottomAnchor, constant: -16)
     ```

3. **Add `showStats()` method:**
   ```swift
   @objc private func showStats() {
       guard #available(iOS 16.0, *) else { return }
       let statsView = DreamingStatsView(
           chartDataPoints: buildChartDataPoints(),
           levelThresholds: Self.levelThresholds,
           externalTimes: DreamingManager.shared.cachedExternalTimes ?? [],
           platformWatchTimeSeconds: DreamingManager.shared.cachedPlatformWatchTimeSeconds ?? 0
       )
       let hostingController = UIHostingController(rootView: statsView)
       present(hostingController, animated: true)
   }
   ```

4. **Remove from `setupUI()`:**
   - Remove `setupChartCard()`, `setupBreakdownCard()`, `setupPodcastBreakdownCard()` calls
   - Remove `stackView.addArrangedSubview(chartCard)`, `stackView.addArrangedSubview(breakdownCard)`, `stackView.addArrangedSubview(podcastBreakdownCard)`

5. **Remove methods:**
   - `setupChartCard()`, `setupBreakdownCard()`, `setupPodcastBreakdownCard()`
   - `updateChartCard()`, `updateBreakdownCard()`, `updatePodcastBreakdownCard()`
   - `buildBreakdownSlices()`, `buildPodcastBreakdownSlices()`
   - `podcastColors` static property

6. **Keep `buildChartDataPoints()`** — it's still needed by `showStats()`

7. **Update `updateCards()`:**
   Remove calls to `updateChartCard()`, `updateBreakdownCard()`, `updatePodcastBreakdownCard()`

8. **Update `applyThemeColors()`:**
   Remove `chartCard.backgroundColor`, `breakdownCard.backgroundColor`, `podcastBreakdownCard.backgroundColor`

**Step 1:** Make all changes
**Step 2:** Verify build: `make build`

---

### Task 4: Format and verify

**Step 1:** Run: `make format`
**Step 2:** Run: `make build`
**Step 3:** Verify only provisioning profile errors, no Swift compilation errors
