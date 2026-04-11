import Charts
import SwiftUI

@available(iOS 17.0, *)
struct DreamingInputBreakdownView: View {
    let title: String
    let slices: [Slice]

    struct Slice: Identifiable {
        let id = UUID()
        let label: String
        let hours: Double
        let color: Color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))

            if slices.isEmpty || slices.allSatisfy({ $0.hours <= 0 }) {
                Text("No data yet")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    Chart(activeSlices) { slice in
                        SectorMark(
                            angle: .value("Hours", slice.hours),
                            innerRadius: .ratio(0.5),
                            angularInset: 1.5
                        )
                        .foregroundStyle(slice.color)
                    }
                    .frame(width: 150, height: 150)

                    legend
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
    }

    private var activeSlices: [Slice] {
        slices.filter { $0.hours > 0 }
    }

    private var totalHours: Double {
        activeSlices.reduce(0) { $0 + $1.hours }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(activeSlices) { slice in
                HStack(spacing: 6) {
                    Circle()
                        .fill(slice.color)
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(slice.label)
                            .font(.system(size: 12, weight: .medium))
                        Text("\(Int(slice.hours))h · \(percentage(slice.hours))")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func percentage(_ hours: Double) -> String {
        guard totalHours > 0 else { return "0%" }
        let pct = (hours / totalHours) * 100
        return String(format: "%.0f%%", pct)
    }
}
