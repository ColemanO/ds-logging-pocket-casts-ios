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
    }

    enum DateRange: Hashable {
        case month(Date) // first day of the month
        case ytd
        case past1Y
        case past2Y
        case past5Y
        case all
    }

    @State private var selectedRange: DateRange = .all

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
            }
        }
        .padding(16)
    }

    // MARK: - Date Range Bar

    private var dateRangeBar: some View {
        HStack(spacing: 6) {
            rangeButton("YTD", isSelected: selectedRange == .ytd) {
                selectedRange = .ytd
            }
            rangeButton("1Y", isSelected: selectedRange == .past1Y) {
                selectedRange = .past1Y
            }
            rangeButton("2Y", isSelected: selectedRange == .past2Y) {
                selectedRange = .past2Y
            }
            rangeButton("5Y", isSelected: selectedRange == .past5Y) {
                selectedRange = .past5Y
            }
            rangeButton("All", isSelected: selectedRange == .all) {
                selectedRange = .all
            }

            Spacer()

            Menu {
                ForEach(availableMonths, id: \.self) { date in
                    Button(monthLabel(date)) {
                        selectedRange = .month(date)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(monthMenuLabel)
                        .font(.system(size: 12, weight: isMonthSelected ? .semibold : .regular))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isMonthSelected ? Color.blue.opacity(0.15) : Color.clear)
                .foregroundColor(isMonthSelected ? .blue : .secondary)
                .cornerRadius(8)
            }
        }
    }

    private func rangeButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.blue.opacity(0.15) : Color.clear)
                .foregroundColor(isSelected ? .blue : .secondary)
                .cornerRadius(8)
        }
    }

    private var isMonthSelected: Bool {
        if case .month = selectedRange { return true }
        return false
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

    // MARK: - Filtering

    private var dateRangeInterval: (start: Date, end: Date)? {
        let cal = Calendar.current
        let now = Date()

        switch selectedRange {
        case .all:
            return nil
        case .ytd:
            let start = cal.date(from: cal.dateComponents([.year], from: now))!
            return (start, now)
        case .past1Y:
            return (cal.date(byAdding: .year, value: -1, to: now)!, now)
        case .past2Y:
            return (cal.date(byAdding: .year, value: -2, to: now)!, now)
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
