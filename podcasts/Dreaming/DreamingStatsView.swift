import SwiftUI

@available(iOS 16.0, *)
struct DreamingStatsView: View {
    let chartDataPoints: [DreamingProgressChartView.DataPoint]
    let levelThresholds: [(level: Int, hours: Double)]
    let externalTimes: [DreamingManager.ExternalTimeEntry]
    let dayWatchedTimes: [DreamingManager.DayWatchedTimeEntry]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedRange: DateRange = .all

    enum DateRange: Hashable {
        case month(Date)
        case past1W, mtd, past1M, ytd, past1Y, all
    }

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
        HStack(spacing: 8) {
            dropdownMenu(label: presetLabel, isActive: isPresetActive) {
                Button("1W") { selectedRange = .past1W }
                Button("MTD") { selectedRange = .mtd }
                Button("1M") { selectedRange = .past1M }
                Button("YTD") { selectedRange = .ytd }
                Button("1Y") { selectedRange = .past1Y }
                Button("All") { selectedRange = .all }
            }

            dropdownMenu(label: monthLabel, isActive: isMonthActive) {
                ForEach(availableMonths, id: \.self) { month in
                    Button(monthFormatter.string(from: month)) {
                        selectedRange = .month(month)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var presetLabel: String {
        switch selectedRange {
        case .past1W: return "1W"
        case .mtd: return "MTD"
        case .past1M: return "1M"
        case .ytd: return "YTD"
        case .past1Y: return "1Y"
        case .all: return "All"
        case .month: return "Preset"
        }
    }

    private var isPresetActive: Bool {
        switch selectedRange {
        case .month: return false
        default: return true
        }
    }

    private var monthLabel: String {
        switch selectedRange {
        case .month(let date): return monthFormatter.string(from: date)
        default: return "Month"
        }
    }

    private var isMonthActive: Bool {
        switch selectedRange {
        case .month: return true
        default: return false
        }
    }

    private var monthFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f
    }

    private func dropdownMenu<Content: View>(label: String, isActive: Bool, @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isActive ? Color.blue.opacity(0.15) : Color.clear)
            .foregroundColor(isActive ? .blue : .secondary)
            .cornerRadius(8)
        }
    }

    // MARK: - Date Range Interval

    private var dateRangeInterval: (start: Date, end: Date)? {
        let cal = Calendar.current
        let now = Date()
        switch selectedRange {
        case .all:
            return nil
        case .past1W:
            return (cal.date(byAdding: .day, value: -7, to: now)!, now)
        case .mtd:
            let comps = cal.dateComponents([.year, .month], from: now)
            return (cal.date(from: comps)!, now)
        case .past1M:
            return (cal.date(byAdding: .month, value: -1, to: now)!, now)
        case .ytd:
            let comps = DateComponents(year: cal.component(.year, from: now), month: 1, day: 1)
            return (cal.date(from: comps)!, now)
        case .past1Y:
            return (cal.date(byAdding: .year, value: -1, to: now)!, now)
        case .month(let monthDate):
            let start = monthDate
            var end = cal.date(byAdding: .month, value: 1, to: start)!
            end = cal.date(byAdding: .second, value: -1, to: end)!
            return (start, end)
        }
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

    // MARK: - Available Months

    private var availableMonths: [Date] {
        let cal = Calendar.current
        var months: [Date] = []
        var seen: Set<String> = []
        for point in chartDataPoints {
            let comps = cal.dateComponents([.year, .month], from: point.date)
            let key = "\(comps.year!)-\(comps.month!)"
            if seen.insert(key).inserted, let first = cal.date(from: comps) {
                months.append(first)
            }
        }
        return months.sorted().reversed()
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

        var podcastSeconds: [(name: String, seconds: Double)] = []
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

        for (key, seconds) in secondsByName {
            podcastSeconds.append((name: seenNames[key]!, seconds: seconds))
        }

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
