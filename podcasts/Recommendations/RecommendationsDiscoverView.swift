import SwiftUI

struct RecommendationsDiscoverView: View {
    @EnvironmentObject var theme: Theme
    @StateObject private var repo = RecommendationsRepository.shared
    @State private var disambiguation: RecommendationDisambiguationPayload?
    @State private var showNoMatchAlert = false
    @State private var showAllSection: RecommendationSection?
    @State private var selectedRegions: Set<String> = []
    @State private var showingRegionFilter = false
    @State private var miniPlayerPadding: CGFloat = 0

    var body: some View {
        stateContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.primaryUi02.ignoresSafeArea(.container, edges: [.bottom, .leading, .trailing]))
            .task { await repo.loadOnAppear() }
            .onAppear {
                miniPlayerPadding = PlaybackManager.shared.currentEpisode() == nil ? 0 : Constants.Values.miniPlayerOffset
            }
            .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.miniPlayerDidAppear)) { _ in
                miniPlayerPadding = Constants.Values.miniPlayerOffset
            }
            .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.miniPlayerDidDisappear)) { _ in
                miniPlayerPadding = 0
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
            .sheet(item: $showAllSection) { section in
                RecommendationsSectionListSheet(section: section)
                    .environmentObject(theme)
            }
            .sheet(isPresented: $showingRegionFilter) {
                RegionFilterSheet(regions: availableRegions, selectedRegions: $selectedRegions)
                    .environmentObject(theme)
            }
            .alert(L10n.recommendationNoMatch, isPresented: $showNoMatchAlert) {
                Button("OK", role: .cancel) {}
            }
    }

    private var availableRegions: [String] {
        let all = repo.snapshot?.sections
            .flatMap { $0.recommendations }
            .compactMap { $0.region }
            ?? []
        return Array(Set(all)).sorted()
    }

    private var filteredSections: [RecommendationSection] {
        guard let sections = repo.snapshot?.sections else { return [] }
        let nonEmpty = sections.filter { !$0.recommendations.isEmpty }
        guard !selectedRegions.isEmpty else { return nonEmpty }
        return nonEmpty.compactMap { section in
            let filtered = section.recommendations.filter { rec in
                guard let region = rec.region else { return false }
                return selectedRegions.contains(region)
            }
            guard !filtered.isEmpty else { return nil }
            var copy = section
            copy.recommendations = filtered
            return copy
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch repo.loadState {
        case .idle, .loading:
            ProgressView().tint(theme.primaryInteractive01)
        case .failed(let message):
            errorView(message)
        case .loaded:
            loadedView
        }
    }

    @ViewBuilder
    private var loadedView: some View {
        let sections = filteredSections
        if sections.isEmpty && availableRegions.isEmpty {
            Text(L10n.recommendationsEmpty)
                .foregroundColor(theme.primaryText02)
        } else {
            VStack(spacing: 0) {
                filterBar
                Divider()
                if sections.isEmpty {
                    Text(L10n.recommendationsEmpty)
                        .foregroundColor(theme.primaryText02)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(sections) { section in
                                RecommendationSectionCard(
                                    section: section,
                                    onTap: handleTap,
                                    onShowAll: { showAllSection = section }
                                )
                            }
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 16 + miniPlayerPadding)
                    }
                    .refreshable { await repo.refresh() }
                }
            }
        }
    }

    private var filterBar: some View {
        HStack {
            Spacer()
            Button {
                showingRegionFilter = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: selectedRegions.isEmpty
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                    Text(selectedRegions.isEmpty
                         ? "All Countries"
                         : "\(selectedRegions.count) \(selectedRegions.count == 1 ? "Country" : "Countries")")
                        .font(.subheadline)
                }
                .foregroundColor(theme.primaryInteractive01)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(theme.primaryInteractive01.opacity(0.1))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
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
                disambiguation = RecommendationDisambiguationPayload(rec: rec, results: results, externalURL: externalURL)
            case .noOptions:
                showNoMatchAlert = true
            }
        }
    }
}

private struct RegionFilterSheet: View {
    @EnvironmentObject var theme: Theme
    @Environment(\.dismiss) private var dismiss
    let regions: [String]
    @Binding var selectedRegions: Set<String>

    var body: some View {
        NavigationView {
            List(regions, id: \.self) { region in
                Button {
                    if selectedRegions.contains(region) {
                        selectedRegions.remove(region)
                    } else {
                        selectedRegions.insert(region)
                    }
                } label: {
                    HStack {
                        Text(region)
                            .foregroundColor(theme.primaryText01)
                        Spacer()
                        if selectedRegions.contains(region) {
                            Image(systemName: "checkmark")
                                .foregroundColor(theme.primaryInteractive01)
                        }
                    }
                }
                .listRowBackground(theme.primaryUi02)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.primaryUi01.ignoresSafeArea())
            .navigationTitle("Filter by Country")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear") { selectedRegions = [] }
                        .disabled(selectedRegions.isEmpty)
                        .foregroundColor(theme.primaryInteractive01)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.done) { dismiss() }
                        .foregroundColor(theme.primaryInteractive01)
                }
            }
        }
    }
}

private struct RecommendationSectionCard: View {
    @EnvironmentObject var theme: Theme
    let section: RecommendationSection
    let onTap: (Recommendation) -> Void
    let onShowAll: () -> Void

    private static let pageSize = 4
    private let rowHeight: CGFloat = 60

    private var pages: [[Recommendation]] {
        stride(from: 0, to: section.recommendations.count, by: Self.pageSize).map {
            Array(section.recommendations[$0 ..< min($0 + Self.pageSize, section.recommendations.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            pager
        }
        .background(theme.primaryUi01)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(section.title)
                .font(.headline)
                .foregroundColor(theme.primaryText01)
            Spacer()
            if section.recommendations.count > Self.pageSize {
                Button(L10n.discoverShowAll.localizedUppercase) { onShowAll() }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(theme.primaryInteractive01)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var pager: some View {
        let showDots = pages.count > 1
        return TabView {
            ForEach(pages.indices, id: \.self) { i in
                pageRows(pages[i])
                    .padding(.bottom, showDots ? 20 : 0)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: showDots ? .always : .never))
        .frame(height: rowHeight * CGFloat(Self.pageSize) + (showDots ? 28 : 0))
    }

    private func pageRows(_ recs: [Recommendation]) -> some View {
        VStack(spacing: 0) {
            ForEach(recs) { rec in
                RecommendationRow(rec: rec)
                    .frame(height: rowHeight)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap(rec) }
                if rec.id != recs.last?.id {
                    Divider().padding(.leading, 56)
                }
            }
            if recs.count < Self.pageSize {
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

private struct RecommendationsSectionListSheet: View {
    @EnvironmentObject var theme: Theme
    @Environment(\.dismiss) private var dismiss

    let section: RecommendationSection

    @State private var disambiguation: RecommendationDisambiguationPayload?
    @State private var showNoMatchAlert = false

    var body: some View {
        NavigationView {
            List {
                ForEach(section.recommendations) { rec in
                    RecommendationRow(rec: rec)
                        .listRowBackground(theme.primaryUi02)
                        .contentShape(Rectangle())
                        .onTapGesture { handleTap(rec) }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.primaryUi01.ignoresSafeArea())
            .navigationTitle(section.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.done) { dismiss() }
                }
            }
        }
        .sheet(item: $disambiguation) { payload in
            RecommendationDisambiguationView(
                payload: payload,
                onPodcastChosen: { uuid in
                    RecommendationsRepository.shared.overrideMatch(.podcast(uuid: uuid), for: payload.rec)
                    dismiss()
                    NavigationManager.sharedManager.navigateTo(
                        NavigationManager.podcastPageKey,
                        data: [NavigationManager.podcastKey: uuid]
                    )
                },
                onExternalChosen: { url in
                    RecommendationsRepository.shared.overrideMatch(.externalOnly(url: url.absoluteString), for: payload.rec)
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            )
            .environmentObject(theme)
        }
        .alert(L10n.recommendationNoMatch, isPresented: $showNoMatchAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    private func handleTap(_ rec: Recommendation) {
        Task {
            let outcome = await RecommendationsRepository.shared.resolve(for: rec)
            switch outcome {
            case .podcast(let uuid):
                dismiss()
                NavigationManager.sharedManager.navigateTo(
                    NavigationManager.podcastPageKey,
                    data: [NavigationManager.podcastKey: uuid]
                )
            case .externalOnly(let urlString):
                if let url = URL(string: urlString) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            case .needsDisambiguation(let results, let externalURL):
                disambiguation = RecommendationDisambiguationPayload(rec: rec, results: results, externalURL: externalURL)
            case .noOptions:
                showNoMatchAlert = true
            }
        }
    }
}
