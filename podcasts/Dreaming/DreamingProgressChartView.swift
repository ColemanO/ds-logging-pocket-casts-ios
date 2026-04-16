import Charts
import SwiftUI

@available(iOS 16.0, *)
struct DreamingProgressChartView: View {
    let dataPoints: [DataPoint]
    let allDataPoints: [DataPoint]
    let levelThresholds: [(level: Int, hours: Double)]

    struct DataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let cumulativeHours: Double
        let goalReached: Bool
    }

    @State private var scrubPoint: DataPoint?
    @State private var pinnedPoint: DataPoint?
    @State private var dragStartTime: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Progress Over Time")
                .font(.system(size: 15, weight: .semibold))

            if dataPoints.isEmpty {
                Text("No data yet")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(dataPoints) { point in
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

                    ForEach(visibleThresholds, id: \.level) { threshold in
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

            if !dataPoints.isEmpty {
                statsBar
            }
        }
        .padding(16)
    }

    // MARK: - Stats

    private var statsBar: some View {
        let points = dataPoints
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
                if let allIndex = allDataPoints.firstIndex(where: { $0.date == points[0].date }), allIndex > 0 {
                    total += points[0].cumulativeHours - allDataPoints[allIndex - 1].cumulativeHours
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

    // MARK: - Scrubbing

    private func closestPoint(to date: Date) -> DataPoint? {
        let points = dataPoints
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

    private var visibleThresholds: [(level: Int, hours: Double)] {
        guard let minHours = dataPoints.first?.cumulativeHours,
              let maxHours = dataPoints.last?.cumulativeHours else { return [] }
        let ceiling = maxHours + (maxHours - minHours) * 0.15
        return levelThresholds.filter { $0.hours > 0 && $0.hours >= minHours && $0.hours <= ceiling }
    }
}
