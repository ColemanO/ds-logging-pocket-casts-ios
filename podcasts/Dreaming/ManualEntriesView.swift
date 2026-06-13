import PocketCastsUtils
import SwiftUI

struct ManualEntriesView: View {
    @EnvironmentObject var theme: Theme

    @State private var entries: [DreamingManager.ExternalTimeEntry] = []
    @State private var showTimer = false
    @State private var showManualEntry = false

    var body: some View {
        ZStack(alignment: .bottom) {
            theme.primaryUi01
                .ignoresSafeArea()

            entriesScrollView

            floatingButtonBar
        }
        .onAppear(perform: loadEntries)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            loadEntries()
        }
        .sheet(isPresented: $showTimer) {
            TalkTimerView(onLogged: loadEntries)
                .environmentObject(theme)
        }
        .sheet(isPresented: $showManualEntry) {
            TalkSessionSummaryView(onLogged: loadEntries)
                .environmentObject(theme)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var entriesScrollView: some View {
        if entries.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries, id: \.id) { entry in
                        entryRow(entry)
                        Divider()
                            .background(theme.primaryUi05)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 100) // room for the floating bar
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No manual entries yet")
                .font(.headline)
                .foregroundColor(theme.primaryText01)
            Text("Tap a button below to log a session")
                .font(.subheadline)
                .foregroundColor(theme.primaryText02)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 100)
    }

    private func entryRow(_ entry: DreamingManager.ExternalTimeEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.description)
                    .font(.subheadline)
                    .foregroundColor(theme.primaryText01)
                    .lineLimit(1)
                Text(formatDate(entry.date))
                    .font(.caption)
                    .foregroundColor(theme.primaryText02)
            }
            Spacer()
            Text(formatDurationShort(entry.timeSeconds))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundColor(theme.primaryText02)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Floating Buttons

    private var floatingButtonBar: some View {
        HStack(spacing: 12) {
            floatingButton(label: "Timer", systemImage: "timer") {
                showTimer = true
            }
            floatingButton(label: "Manual", systemImage: "plus.circle.fill") {
                showManualEntry = true
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    private func floatingButton(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(label)
                    .fontWeight(.semibold)
            }
            .foregroundColor(theme.primaryUi01)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(theme.primaryInteractive01)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
        }
    }

    // MARK: - Data Loading

    private func loadEntries() {
        if let cached = DreamingManager.shared.cachedExternalTimes {
            entries = filterAndSort(cached)
        } else {
            DreamingManager.shared.fetchExternalTimes { fetched in
                DispatchQueue.main.async {
                    if let fetched = fetched {
                        entries = filterAndSort(fetched)
                    }
                }
            }
        }
    }

    private func filterAndSort(_ entries: [DreamingManager.ExternalTimeEntry]) -> [DreamingManager.ExternalTimeEntry] {
        entries
            .filter { isManualEntry($0) }
            .sorted { $0.date > $1.date }
    }

    /// Identifies manual entries (vs auto-logged podcast plays). For now manual
    /// entries are everything with type == "talking"; this will broaden when we
    /// add other manual categories (YouTube, TV, etc.) using description prefixes.
    private func isManualEntry(_ entry: DreamingManager.ExternalTimeEntry) -> Bool {
        entry.type == "talking"
    }

    // MARK: - Formatting

    private func formatDate(_ dateString: String) -> String {
        guard let date = DateFormatHelper.sharedHelper.dayDate(dateString) else { return dateString }
        return DateFormatHelper.sharedHelper.tinyLocalizedFormat(date)
    }

    private func formatDurationShort(_ totalSeconds: Double) -> String {
        let total = Int(totalSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }
}
