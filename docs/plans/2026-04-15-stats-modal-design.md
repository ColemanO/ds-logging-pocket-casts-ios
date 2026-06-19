# Stats Modal Design

## Overview

Move the three chart cards (progress over time, input breakdown, podcast breakdown) from the main Dreaming tab into a dedicated SwiftUI stats modal. Add a "View Stats" button to the total/level card that presents this modal as a sheet.

## Main Dreaming Tab Changes

- Remove `chartCard`, `breakdownCard`, `podcastBreakdownCard` from the stack view
- Remove their hosting controllers and setup code
- Add a "View Stats" button at the bottom of `totalLevelCard`
- Button presents the new `DreamingStatsView` as a modal sheet via UIHostingController

## Stats Modal (SwiftUI)

### Layout (top to bottom)
1. **Navigation bar** with title "Stats" and close button
2. **Page-wide date range selector** — two dropdown menus (preset range + month picker), same style as the existing `DreamingProgressChartView` dropdowns
3. **Progress Over Time chart** — reuses `DreamingProgressChartView` but without its own date range bar (filtering is handled by the parent)
4. **Input Breakdown pie chart** — `DreamingInputBreakdownView` filtered to selected range
5. **Podcast Breakdown pie chart** — `DreamingInputBreakdownView` filtered to selected range

### Date Range Selector
Same options as before: 1W, MTD, 1M, YTD, 1Y, All, plus monthly picker. One selector filters all three charts.

### Data Flow
- On appear, uses cached data from `DreamingManager` (cachedDayWatchedTimes, cachedExternalTimes)
- Selected date range filters all three datasets
- Breakdown charts filter `ExternalTimeEntry` items by date field
- Progress chart receives pre-filtered data points

## Key Files

| File | Change |
|------|--------|
| `podcasts/Dreaming/DreamingStatsView.swift` | New — SwiftUI stats modal with date selector and three charts |
| `podcasts/Dreaming/DreamingProgressViewController.swift` | Remove chart cards, add "View Stats" button |
| `podcasts/Dreaming/DreamingProgressChartView.swift` | Remove internal date range bar, accept pre-filtered data |
