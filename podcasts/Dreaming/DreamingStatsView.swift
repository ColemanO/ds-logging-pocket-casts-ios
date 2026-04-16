import SwiftUI

@available(iOS 16.0, *)
struct DreamingStatsView: View {
    let chartDataPoints: [DreamingProgressChartView.DataPoint]
    let levelThresholds: [(level: Int, hours: Double)]
    let externalTimes: [DreamingManager.ExternalTimeEntry]
    let dayWatchedTimes: [DreamingManager.DayWatchedTimeEntry]

    @Environment(\.dismiss) private var dismiss

    enum Period: String, CaseIterable {
        case week = "Week"
        case month = "Month"
        case year = "Year"
        case all = "All"
    }

    @State private var period: Period = .all
    @State private var offset: Int = 0 // 0 = current, -1 = previous, etc.

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    dateRangeSelector

                    DreamingProgressChartView(
                        dataPoints: filteredChartPoints,
                        allDataPoints: chartDataPoints,
                        levelThresholds: levelThresholds
                    )

                    if #available(iOS 17.0, *) {
                        DreamingInputBreakdownView(title: "Input Breakdown", slices: inputBreakdownSlices)
                        DreamingInputBreakdownView(title: "Podcast Breakdown", slices: podcastBreakdownSlices)
                    }
                }
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Date Range Selector

    private var dateRangeSelector: some View {
        HStack(spacing: 12) {
            periodDropdown

            if period != .all {
                Button(action: { offset -= 1 }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                }
                .disabled(!canGoBack)

                Text(periodLabel)
                    .font(.system(size: 13, weight: .medium))
                    .frame(minWidth: 80)

                Button(action: { offset += 1 }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                }
                .disabled(offset >= 0)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var periodDropdown: some View {
        Menu {
            ForEach(Period.allCases, id: \.self) { p in
                Button(p.rawValue) {
                    period = p
                    offset = 0
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(period.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.blue.opacity(0.15))
            .foregroundColor(.blue)
            .cornerRadius(8)
        }
    }

    // MARK: - Period Label

    private var periodLabel: String {
        let cal = Calendar.current
        let now = Date()

        switch period {
        case .week:
            let weekStart = cal.date(byAdding: .weekOfYear, value: offset, to: startOfWeek(now))!
            let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart)!
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d"
            return "\(fmt.string(from: weekStart)) – \(fmt.string(from: weekEnd))"
        case .month:
            let monthStart = cal.date(byAdding: .month, value: offset, to: startOfMonth(now))!
            let fmt = DateFormatter()
            fmt.dateFormat = "MMMM yyyy"
            return fmt.string(from: monthStart)
        case .year:
            let yearStart = cal.date(byAdding: .year, value: offset, to: startOfYear(now))!
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy"
            return fmt.string(from: yearStart)
        case .all:
            return "All"
        }
    }

    private var canGoBack: Bool {
        guard let earliest = chartDataPoints.first?.date else { return false }
        guard let interval = dateRangeInterval else { return false }
        return interval.start > earliest
    }

    // MARK: - Date Range Interval

    private var dateRangeInterval: (start: Date, end: Date)? {
        let cal = Calendar.current
        let now = Date()

        switch period {
        case .all:
            return nil
        case .week:
            let weekStart = cal.date(byAdding: .weekOfYear, value: offset, to: startOfWeek(now))!
            let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart)!
            return (weekStart, min(weekEnd, now))
        case .month:
            let monthStart = cal.date(byAdding: .month, value: offset, to: startOfMonth(now))!
            let monthEnd = cal.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)!
            return (monthStart, min(monthEnd, now))
        case .year:
            let yearStart = cal.date(byAdding: .year, value: offset, to: startOfYear(now))!
            let yearEnd = cal.date(byAdding: DateComponents(year: 1, day: -1), to: yearStart)!
            return (yearStart, min(yearEnd, now))
        }
    }

    // MARK: - Calendar Helpers

    private func startOfWeek(_ date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps)!
    }

    private func startOfMonth(_ date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps)!
    }

    private func startOfYear(_ date: Date) -> Date {
        let cal = Calendar.current
        let comps = DateComponents(year: cal.component(.year, from: date), month: 1, day: 1)
        return cal.date(from: comps)!
    }

    // MARK: - Filtered Data

    private var filteredChartPoints: [DreamingProgressChartView.DataPoint] {
        guard let interval = dateRangeInterval else { return chartDataPoints }
        return chartDataPoints.filter { $0.date >= interval.start && $0.date <= interval.end }
    }

    private var filteredExternalTimes: [DreamingManager.ExternalTimeEntry] {
        guard let interval = dateRangeInterval else { return externalTimes }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return externalTimes.filter { entry in
            guard let date = formatter.date(from: entry.date) else { return false }
            return date >= interval.start && date <= interval.end
        }
    }

    private var filteredDayWatchedTimes: [DreamingManager.DayWatchedTimeEntry] {
        guard let interval = dateRangeInterval else { return dayWatchedTimes }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return dayWatchedTimes.filter { entry in
            guard let date = formatter.date(from: entry.date) else { return false }
            return date >= interval.start && date <= interval.end
        }
    }

    /// Dreaming Spanish platform time = total day watched time - non-initial external time
    private var filteredPlatformSeconds: Double {
        let totalDaySeconds = filteredDayWatchedTimes.reduce(0.0) { $0 + $1.timeSeconds }
        let nonInitialExternalSeconds = filteredExternalTimes
            .filter { $0.type != "initial" }
            .reduce(0.0) { $0 + $1.timeSeconds }
        return max(totalDaySeconds - nonInitialExternalSeconds, 0)
    }

    // MARK: - Input Breakdown Slices

    @available(iOS 17.0, *)
    private var inputBreakdownSlices: [DreamingInputBreakdownView.Slice] {
        var grouped: [String: (label: String, seconds: Double, color: Color)] = [:]
        let typeMap: [(key: String, label: String, color: Color)] = [
            ("initial", "Initial", .gray),
            ("listening", "Podcasts", .green),
            ("watching", "External Videos", .orange),
            ("talking", "Talking", .purple),
        ]

        for entry in filteredExternalTimes {
            for mapping in typeMap where mapping.key == entry.type {
                let existing = grouped[mapping.key] ?? (label: mapping.label, seconds: 0, color: mapping.color)
                grouped[mapping.key] = (label: existing.label, seconds: existing.seconds + entry.timeSeconds, color: existing.color)
            }
        }

        var slices = typeMap.compactMap { mapping -> DreamingInputBreakdownView.Slice? in
            guard let data = grouped[mapping.key] else { return nil }
            return DreamingInputBreakdownView.Slice(label: data.label, hours: data.seconds / 3600.0, color: data.color)
        }

        // Dreaming Spanish platform time (derived from day totals minus external entries)
        let platformHours = filteredPlatformSeconds / 3600.0
        if platformHours > 0 {
            slices.insert(DreamingInputBreakdownView.Slice(label: "Dreaming Spanish", hours: platformHours, color: .blue), at: 0)
        }

        return slices
    }

    // MARK: - Podcast Breakdown Slices

    @available(iOS 17.0, *)
    private var podcastBreakdownSlices: [DreamingInputBreakdownView.Slice] {
        let listeningEntries = filteredExternalTimes.filter { $0.type == "listening" }
        let episodeSuffixPattern = #"\s*-\s*[Ee]ps?\s*[\d:,\s\-]+$"#

        var seenNames: [String: String] = [:] // lowercased -> first-seen display name
        var secondsByName: [String: Double] = [:]

        for entry in listeningEntries {
            let stripped = entry.description.replacingOccurrences(of: episodeSuffixPattern, with: "", options: .regularExpression)
            let key = stripped.lowercased()
            if seenNames[key] == nil {
                seenNames[key] = stripped
            }
            secondsByName[key, default: 0] += entry.timeSeconds
        }

        var podcastSeconds = secondsByName.map { (name: seenNames[$0.key]!, seconds: $0.value) }
        podcastSeconds.sort { $0.seconds > $1.seconds }

        let totalSeconds = podcastSeconds.reduce(0.0) { $0 + $1.seconds }
        let rotatingColors: [Color] = [.blue, .green, .orange, .purple, .pink, .red, .teal, .indigo, .mint, .cyan, .brown, .yellow]

        var slices: [DreamingInputBreakdownView.Slice] = []
        var otherSeconds = 0.0
        var colorIndex = 0

        for podcast in podcastSeconds {
            let pct = totalSeconds > 0 ? (podcast.seconds / totalSeconds) * 100 : 0
            if pct < 1 {
                otherSeconds += podcast.seconds
            } else {
                slices.append(DreamingInputBreakdownView.Slice(
                    label: podcast.name,
                    hours: podcast.seconds / 3600.0,
                    color: rotatingColors[colorIndex % rotatingColors.count]
                ))
                colorIndex += 1
            }
        }

        if otherSeconds > 0 {
            slices.append(DreamingInputBreakdownView.Slice(label: "Other", hours: otherSeconds / 3600.0, color: .gray))
        }

        return slices
    }
}
