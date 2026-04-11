import Charts
import SwiftUI

@available(iOS 16.0, *)
struct DreamingProgressChartView: View {
    let dataPoints: [DataPoint]
    let levelThresholds: [(level: Int, hours: Double)]

    struct DataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let cumulativeHours: Double
        let goalReached: Bool
    }

    enum DateRange: Hashable {
        case month(Date) // specific month picker
        case past1W
        case mtd
        case past1M
        case ytd
        case past1Y
        case past5Y
        case all
    }

    @State private var selectedRange: DateRange = .all
    @State private var scrubPoint: DataPoint?
    @State private var pinnedPoint: DataPoint?
    @State private var dragStartTime: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Progress Over Time")
                .font(.system(size: 15, weight: .semibold))

            dateRangeBar

            if filteredPoints.isEmpty {
                Text("No data yet")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(filteredPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Hours", point.cumulativeHours)
                        )
                        .foregroundStyle(Color.blue)

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Hours", point.cumulativeHours)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.2), Color.blue.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }

                    ForEach(filteredThresholds, id: \.level) { threshold in
                        RuleMark(y: .value("Level", threshold.hours))
                            .foregroundStyle(.gray.opacity(0.5))
                            .lineStyle(StrokeStyle(dash: [5, 5]))
                            .annotation(position: .topLeading) {
                                Text("L\(threshold.level)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                    }

                    if let pinned = pinnedPoint {
                        RuleMark(x: .value("Date", pinned.date))
                            .foregroundStyle(.orange.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                        PointMark(
                            x: .value("Date", pinned.date),
                            y: .value("Hours", pinned.cumulativeHours)
                        )
                        .foregroundStyle(Color.orange)
                        .symbolSize(40)
                    }

                    if let scrub = scrubPoint {
                        RuleMark(x: .value("Date", scrub.date))
                            .foregroundStyle(.gray.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .annotation(position: .top, spacing: 4) {
                                scrubAnnotation(scrub: scrub)
                            }

                        PointMark(
                            x: .value("Date", scrub.date),
                            y: .value("Hours", scrub.cumulativeHours)
                        )
                        .foregroundStyle(Color.blue)
                        .symbolSize(40)
                    }
                }
                .frame(height: 200)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let hours = value.as(Double.self) {
                                Text("\(Int(hours))h")
                                    .font(.system(size: 10))
                            }
                        }
                        AxisGridLine()
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 10))
                        AxisGridLine()
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let origin = geometry[proxy.plotAreaFrame].origin
                                        let x = value.location.x - origin.x
                                        guard let date: Date = proxy.value(atX: x) else { return }
                                        let point = closestPoint(to: date)

                                        if dragStartTime == nil {
                                            dragStartTime = Date()
                                        }

                                        // Pin after holding ~2s in roughly the same spot
                                        if pinnedPoint == nil,
                                           let start = dragStartTime,
                                           Date().timeIntervalSince(start) > 2.0,
                                           let scrub = scrubPoint, let pt = point,
                                           abs(scrub.date.timeIntervalSince(pt.date)) < 86400 {
                                            pinnedPoint = scrub
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        }

                                        scrubPoint = point
                                    }
                                    .onEnded { _ in
                                        scrubPoint = nil
                                        pinnedPoint = nil
                                        dragStartTime = nil
                                    }
                            )
                    }
                }
            }

            if !filteredPoints.isEmpty {
                statsBar
            }
        }
        .padding(16)
    }

    // MARK: - Stats

    private var statsBar: some View {
        let points = filteredPoints
        let totalHours = periodTotalHours(points)
        let days = max(points.count, 1)
        let avgDaily = totalHours / Double(days)
        let goalsHit = points.filter { $0.goalReached }.count

        return HStack(spacing: 0) {
            statItem(value: String(format: "%.1fh", totalHours), label: "Total")
            statItem(value: String(format: "%.1fh", avgDaily), label: "Daily Avg")
            statItem(value: "\(goalsHit) / \(days)", label: "Goals Hit")
        }
    }

    private func periodTotalHours(_ points: [DataPoint]) -> Double {
        guard !points.isEmpty else { return 0 }
        var total = 0.0
        for i in 0..<points.count {
            if i == 0 {
                // Find this point in the full dataset to get the previous day's cumulative
                if let allIndex = dataPoints.firstIndex(where: { $0.date == points[0].date }), allIndex > 0 {
                    total += points[0].cumulativeHours - dataPoints[allIndex - 1].cumulativeHours
                }
            } else {
                total += points[i].cumulativeHours - points[i - 1].cumulativeHours
            }
        }
        return total
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold))
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Date Range Bar

    private static let presetRanges: [(label: String, range: DateRange)] = [
        ("1W", .past1W),
        ("MTD", .mtd),
        ("1M", .past1M),
        ("YTD", .ytd),
        ("1Y", .past1Y),
        ("All", .all),
    ]

    private var dateRangeBar: some View {
        HStack(spacing: 8) {
            dropdownMenu(label: rangeMenuLabel, isActive: !isMonthSelected) {
                ForEach(Self.presetRanges, id: \.label) { preset in
                    Button(preset.label) {
                        selectedRange = preset.range
                    }
                }
            }

            dropdownMenu(label: monthMenuLabel, isActive: isMonthSelected) {
                ForEach(availableMonths, id: \.self) { date in
                    Button(monthLabel(date)) {
                        selectedRange = .month(date)
                    }
                }
            }

            Spacer()
        }
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

    private var isMonthSelected: Bool {
        if case .month = selectedRange { return true }
        return false
    }

    private var rangeMenuLabel: String {
        for preset in Self.presetRanges where preset.range == selectedRange {
            return preset.label
        }
        return "Range"
    }

    private var monthMenuLabel: String {
        if case .month(let date) = selectedRange {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM yyyy"
            return formatter.string(from: date)
        }
        return "Month"
    }

    private var availableMonths: [Date] {
        let cal = Calendar.current
        var months: [Date] = []
        var seen: Set<String> = []
        for point in dataPoints {
            let comps = cal.dateComponents([.year, .month], from: point.date)
            let key = "\(comps.year!)-\(comps.month!)"
            if seen.insert(key).inserted, let first = cal.date(from: comps) {
                months.append(first)
            }
        }
        return months.sorted().reversed()
    }

    private func monthLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    // MARK: - Scrubbing

    private func closestPoint(to date: Date) -> DataPoint? {
        let points = filteredPoints
        guard !points.isEmpty else { return nil }
        return points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private func scrubDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    @ViewBuilder
    private func scrubAnnotation(scrub: DataPoint) -> some View {
        if let pinned = pinnedPoint {
            let delta = scrub.cumulativeHours - pinned.cumulativeHours
            let days = Calendar.current.dateComponents([.day], from: pinned.date, to: scrub.date).day ?? 0
            VStack(spacing: 2) {
                Text("\(delta >= 0 ? "+" : "")\(Int(delta))h")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(delta >= 0 ? .green : .red)
                Text("\(abs(days))d")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(UIColor.systemBackground).opacity(0.9))
            .cornerRadius(4)
            .shadow(radius: 1)
        } else {
            VStack(spacing: 2) {
                Text("\(Int(scrub.cumulativeHours))h")
                    .font(.system(size: 11, weight: .semibold))
                Text(scrubDateLabel(scrub.date))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(UIColor.systemBackground).opacity(0.9))
            .cornerRadius(4)
            .shadow(radius: 1)
        }
    }

    // MARK: - Filtering

    private var dateRangeInterval: (start: Date, end: Date)? {
        let cal = Calendar.current
        let now = Date()

        switch selectedRange {
        case .all:
            return nil
        case .past1W:
            return (cal.date(byAdding: .day, value: -7, to: now)!, now)
        case .mtd:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: now))!
            return (start, now)
        case .past1M:
            return (cal.date(byAdding: .month, value: -1, to: now)!, now)
        case .ytd:
            let start = cal.date(from: cal.dateComponents([.year], from: now))!
            return (start, now)
        case .past1Y:
            return (cal.date(byAdding: .year, value: -1, to: now)!, now)
        case .past5Y:
            return (cal.date(byAdding: .year, value: -5, to: now)!, now)
        case .month(let monthStart):
            let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)!
            return (monthStart, end)
        }
    }

    private var filteredPoints: [DataPoint] {
        guard let interval = dateRangeInterval else { return dataPoints }
        return dataPoints.filter { $0.date >= interval.start && $0.date <= interval.end }
    }

    private var filteredThresholds: [(level: Int, hours: Double)] {
        guard let minHours = filteredPoints.first?.cumulativeHours,
              let maxHours = filteredPoints.last?.cumulativeHours else { return [] }
        let ceiling = maxHours + (maxHours - minHours) * 0.15
        return levelThresholds.filter { $0.hours > 0 && $0.hours >= minHours && $0.hours <= ceiling }
    }
}
