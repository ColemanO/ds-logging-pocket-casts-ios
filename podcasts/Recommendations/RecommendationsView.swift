import PocketCastsServer
import SwiftUI

struct RecommendationsView: View {
    @EnvironmentObject var theme: Theme
    @StateObject private var repo = RecommendationsRepository.shared
    @State private var expandedSections: Set<Int> = []
    @State private var disambiguation: RecommendationDisambiguationPayload?
    @State private var showNoMatchAlert = false

    var body: some View {
        ZStack {
            theme.primaryUi01.ignoresSafeArea()
            content
        }
        .task {
            await repo.loadOnAppear()
            initializeExpansionIfNeeded()
        }
        .refreshable {
            await repo.refresh()
            initializeExpansionIfNeeded()
        }
        .sheet(item: $disambiguation) { payload in
            RecommendationDisambiguationView(
                payload: payload,
                onPodcastChosen: { uuid in
                    repo.overrideMatch(.podcast(uuid: uuid), for: payload.rec)
                    NavigationManager.sharedManager.navigateTo(
                        NavigationManager.podcastPageKey,
                        data: [NavigationManager.podcastKey: uuid]
                    )
                },
                onExternalChosen: { url in
                    repo.overrideMatch(.externalOnly(url: url.absoluteString), for: payload.rec)
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            )
            .environmentObject(theme)
        }
        .alert(L10n.recommendationNoMatch, isPresented: $showNoMatchAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var content: some View {
        switch repo.loadState {
        case .idle, .loading:
            ProgressView().tint(theme.primaryInteractive01)
        case .failed(let message):
            errorView(message)
        case .loaded:
            if let sections = repo.snapshot?.sections, !sections.isEmpty {
                list(sections: sections)
            } else {
                Text(L10n.recommendationsEmpty)
                    .foregroundColor(theme.primaryText02)
            }
        }
    }

    private func list(sections: [RecommendationSection]) -> some View {
        List {
            ForEach(sections) { section in
                Section {
                    if expandedSections.contains(section.level) {
                        ForEach(section.recommendations) { rec in
                            RecommendationRow(rec: rec)
                                .listRowBackground(theme.primaryUi02)
                                .contentShape(Rectangle())
                                .onTapGesture { handleTap(rec) }
                        }
                    }
                } header: {
                    sectionHeader(section)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func sectionHeader(_ section: RecommendationSection) -> some View {
        Button(action: { toggleSection(section.level) }) {
            HStack {
                Text(section.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(theme.primaryText02)
                Spacer()
                Image(systemName: expandedSections.contains(section.level) ? "chevron.down" : "chevron.right")
                    .foregroundColor(theme.primaryText02)
                    .font(.caption.weight(.bold))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text(message)
                .foregroundColor(theme.primaryText01)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(L10n.recommendationRetry) {
                Task { await repo.refresh() }
            }
            .foregroundColor(theme.primaryInteractive01)
            .fontWeight(.semibold)
        }
    }

    // MARK: - Actions

    private func toggleSection(_ level: Int) {
        if expandedSections.contains(level) {
            expandedSections.remove(level)
        } else {
            expandedSections.insert(level)
        }
    }

    private func handleTap(_ rec: Recommendation) {
        Task {
            let outcome = await repo.resolve(for: rec)
            switch outcome {
            case .podcast(let uuid):
                NavigationManager.sharedManager.navigateTo(
                    NavigationManager.podcastPageKey,
                    data: [NavigationManager.podcastKey: uuid]
                )
            case .externalOnly(let urlString):
                if let url = URL(string: urlString) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            case .needsDisambiguation(let results, let externalURL):
                disambiguation = RecommendationDisambiguationPayload(
                    rec: rec, results: results, externalURL: externalURL
                )
            case .noOptions:
                showNoMatchAlert = true
            }
        }
    }

    // MARK: - Section expansion

    private func initializeExpansionIfNeeded() {
        guard expandedSections.isEmpty, let sections = repo.snapshot?.sections else { return }
        let totalSeconds = DreamingManager.shared.cachedTotalInputSeconds ?? 0
        let totalHours = totalSeconds / 3600
        if totalHours <= 0 {
            expandedSections = Set(sections.map(\.level))
            return
        }
        let userLevel = sections
            .filter { Double($0.hourThreshold) <= totalHours }
            .map(\.level)
            .max() ?? 1
        expandedSections = Set(sections.filter { $0.level <= userLevel }.map(\.level))
        if expandedSections.isEmpty {
            expandedSections = Set(sections.map(\.level))
        }
    }
}
