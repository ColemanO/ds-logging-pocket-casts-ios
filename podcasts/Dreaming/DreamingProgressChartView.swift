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

                    ForEach(relevantThresholds, id: \.level) { threshold in
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

    private var relevantThresholds: [(level: Int, hours: Double)] {
        guard let maxHours = dataPoints.last?.cumulativeHours else { return [] }
        let ceiling = maxHours * 1.3
        return levelThresholds.filter { $0.hours > 0 && $0.hours <= ceiling }
    }
}
