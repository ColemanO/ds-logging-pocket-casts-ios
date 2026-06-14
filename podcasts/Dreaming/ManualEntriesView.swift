import PocketCastsUtils
import SwiftUI
import UIKit

/// Filter categories shown in the Activity tab chip row. Each case maps to a
/// Dreaming Spanish `type` field except `.all`, which disables filtering.
enum EntryCategory: String, CaseIterable, Identifiable {
    case all
    case podcasts    // DS type "listening"
    case talking     // DS type "talking"
    case watching    // DS type "watching"
    case initial     // DS type "initial"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All"
        case .podcasts: return "Podcasts"
        case .talking: return "Talking"
        case .watching: return "Watching"
        case .initial: return "Initial"
        }
    }

    /// The Dreaming Spanish `type` field this category matches.
    /// `nil` for `.all` (no filter applied).
    var apiType: String? {
        switch self {
        case .all: return nil
        case .podcasts: return "listening"
        case .talking: return "talking"
        case .watching: return "watching"
        case .initial: return "initial"
        }
    }
}

/// Bridges the UIKit bar-button menu (in `ManualEntriesViewController`) to the
/// SwiftUI sheet presentations in `ManualEntriesView`.
final class ManualEntriesCoordinator: ObservableObject {
    @Published var showTimer = false
    @Published var showManualEntry = false
}

/// Hosts `ManualEntriesView` and adds a right-bar "+" button with a menu of
/// entry options (Timer, Manual). The menu drives the coordinator, which the
/// SwiftUI view observes to present the appropriate sheet.
final class ManualEntriesViewController: ThemedHostingController<ManualEntriesView> {
    private let coordinator: ManualEntriesCoordinator

    init() {
        let coordinator = ManualEntriesCoordinator()
        self.coordinator = coordinator
        super.init(rootView: ManualEntriesView(coordinator: coordinator), background: \.primaryUi01)
        title = "Manual Entries"
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupAddButton()
    }

    private func setupAddButton() {
        let timerAction = UIAction(title: "Timer", image: UIImage(systemName: "timer")) { [weak self] _ in
            self?.coordinator.showTimer = true
        }
        let manualAction = UIAction(title: "Manual", image: UIImage(systemName: "square.and.pencil")) { [weak self] _ in
            self?.coordinator.showManualEntry = true
        }
        let menu = UIMenu(children: [timerAction, manualAction])
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "plus"), menu: menu)
    }
}

struct ManualEntriesView: View {
    @EnvironmentObject var theme: Theme
    @ObservedObject var coordinator: ManualEntriesCoordinator

    @State private var allEntries: [DreamingManager.ExternalTimeEntry] = []
    @State private var selectedCategory: EntryCategory = .all

    private var displayedEntries: [DreamingManager.ExternalTimeEntry] {
        filterAndSort(allEntries)
    }

    var body: some View {
        ZStack {
            theme.primaryUi01
                .ignoresSafeArea()

            VStack(spacing: 0) {
                chipRow
                entriesScrollView
            }
        }
        .onAppear(perform: loadEntries)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            loadEntries()
        }
        .sheet(isPresented: $coordinator.showTimer) {
            TalkTimerView(onLogged: loadEntries)
                .environmentObject(theme)
        }
        .sheet(isPresented: $coordinator.showManualEntry) {
            TalkSessionSummaryView(onLogged: loadEntries)
                .environmentObject(theme)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var entriesScrollView: some View {
        if displayedEntries.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(displayedEntries, id: \.id) { entry in
                        entryRow(entry)
                        Divider()
                            .background(theme.primaryUi05)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(emptyStateTitle)
                .font(.headline)
                .foregroundColor(theme.primaryText01)
            Text("Tap + in the top right to log a session")
                .font(.subheadline)
                .foregroundColor(theme.primaryText02)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateTitle: String {
        switch selectedCategory {
        case .all:
            return "No entries yet"
        default:
            return "No \(selectedCategory.displayName.lowercased()) entries yet"
        }
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

    // MARK: - Filter Chips

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EntryCategory.allCases) { category in
                    categoryChip(category)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(theme.primaryUi01)
    }

    private func categoryChip(_ category: EntryCategory) -> some View {
        let isSelected = selectedCategory == category
        return Button(action: { selectedCategory = category }) {
            Text(category.displayName)
                .font(.subheadline.weight(.semibold))
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .foregroundColor(isSelected ? theme.primaryUi01 : theme.primaryText01)
                .background(isSelected ? theme.primaryInteractive01 : theme.primaryUi02)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data Loading

    private func loadEntries() {
        if let cached = DreamingManager.shared.cachedExternalTimes {
            allEntries = cached
        } else {
            DreamingManager.shared.fetchExternalTimes { fetched in
                DispatchQueue.main.async {
                    if let fetched = fetched {
                        allEntries = fetched
                    }
                }
            }
        }
    }

    private func filterAndSort(_ entries: [DreamingManager.ExternalTimeEntry]) -> [DreamingManager.ExternalTimeEntry] {
        entries
            .filter { matchesSelectedCategory($0) }
            .sorted { $0.date > $1.date }
    }

    private func matchesSelectedCategory(_ entry: DreamingManager.ExternalTimeEntry) -> Bool {
        guard let apiType = selectedCategory.apiType else { return true } // .all
        return entry.type == apiType
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
