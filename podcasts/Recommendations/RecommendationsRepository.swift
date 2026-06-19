import Foundation
import PocketCastsServer
import PocketCastsUtils

/// Resolution returned by `RecommendationsRepository.resolve(for:)`.
/// Transient, not persisted. The persisted form is `RecommendationMatch`.
enum RecommendationResolution {
    case podcast(uuid: String)
    case externalOnly(url: String)
    case needsDisambiguation(results: [PodcastFolderSearchResult], externalURL: URL?)
    case noOptions
}

enum RecommendationsError: Error {
    case fetchFailed
    case decodingFailed
}

@MainActor
final class RecommendationsRepository: ObservableObject {
    static let shared = RecommendationsRepository()

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(message: String)
    }

    @Published private(set) var snapshot: RecommendationsSnapshot?
    @Published private(set) var matches: [String: RecommendationMatch] = [:]
    @Published private(set) var loadState: LoadState = .idle

    private let csvURL = URL(string:
        "https://docs.google.com/spreadsheets/d/1lBmLxvWJpucXhRPayfXD7CVqpMoa2tyEbZi1rFAwsFs/export?format=csv&gid=0"
    )!

    private let missTTL: TimeInterval = 30 * 86_400
    private let snapshotMaxAge: TimeInterval = 3_600

    private var inFlightFetch: Task<Void, Never>?
    private var didLoadCaches = false

    private init() {}

    // MARK: - Public API

    func loadOnAppear() async {
        loadCachesFromDiskIfNeeded()

        if snapshot != nil {
            loadState = .loaded
            if let fetchedAt = snapshot?.fetchedAt,
               Date().timeIntervalSince(fetchedAt) > snapshotMaxAge {
                backgroundRefresh()
            }
        } else {
            loadState = .loading
            await foregroundFetch()
        }
    }

    func refresh() async {
        await foregroundFetch(forceUserSurface: true)
    }

    func resolve(for rec: Recommendation) async -> RecommendationResolution {
        loadCachesFromDiskIfNeeded()

        if let cached = matches[rec.matchKey] {
            switch cached {
            case .podcast(let uuid):
                return .podcast(uuid: uuid)
            case .externalOnly(let url):
                return .externalOnly(url: url)
            case .miss(let checkedAt) where Date().timeIntervalSince(checkedAt) <= missTTL:
                if let ext = externalURL(for: rec) {
                    return .needsDisambiguation(results: [], externalURL: ext)
                } else {
                    return .noOptions
                }
            case .miss:
                break // expired; re-search
            }
        }

        let results: [PodcastFolderSearchResult]
        do {
            results = try await PodcastSearchTask().search(term: rec.title)
        } catch {
            if let ext = externalURL(for: rec) {
                return .needsDisambiguation(results: [], externalURL: ext)
            } else {
                return .noOptions
            }
        }

        if let top = results.first,
           let topTitle = top.title,
           RecommendationFuzzyMatch.matches(rec.title, topTitle) {
            matches[rec.matchKey] = .podcast(uuid: top.uuid)
            persistMatches()
            return .podcast(uuid: top.uuid)
        }

        let ext = externalURL(for: rec)
        if results.isEmpty, ext == nil {
            matches[rec.matchKey] = .miss(checkedAt: Date())
            persistMatches()
            return .noOptions
        }
        return .needsDisambiguation(results: results, externalURL: ext)
    }

    func overrideMatch(_ match: RecommendationMatch, for rec: Recommendation) {
        matches[rec.matchKey] = match
        persistMatches()
    }

    func cachedMatch(for rec: Recommendation) -> RecommendationMatch? {
        loadCachesFromDiskIfNeeded()
        return matches[rec.matchKey]
    }

    // MARK: - Disk cache

    private var cachesDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }
    private var snapshotFile: URL { cachesDir.appendingPathComponent("recommendations_csv.json") }
    private var matchesFile: URL { cachesDir.appendingPathComponent("recommendations_matches.json") }

    private func loadCachesFromDiskIfNeeded() {
        guard !didLoadCaches else { return }
        didLoadCaches = true
        loadSnapshotFromDisk()
        loadMatchesFromDisk()
    }

    private func loadSnapshotFromDisk() {
        guard let data = try? Data(contentsOf: snapshotFile),
              let decoded = try? JSONDecoder().decode(RecommendationsSnapshot.self, from: data)
        else {
            return
        }
        snapshot = decoded
    }

    private func loadMatchesFromDisk() {
        guard let data = try? Data(contentsOf: matchesFile),
              let decoded = try? JSONDecoder().decode([String: RecommendationMatch].self, from: data)
        else {
            return
        }
        matches = decoded
    }

    private func persistSnapshot(_ snapshot: RecommendationsSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: snapshotFile, options: .atomic)
    }

    private func persistMatches() {
        guard let data = try? JSONEncoder().encode(matches) else { return }
        try? data.write(to: matchesFile, options: .atomic)
    }

    // MARK: - Fetch

    private func foregroundFetch(forceUserSurface _: Bool = false) async {
        do {
            let fresh = try await fetchCSV()
            snapshot = fresh
            persistSnapshot(fresh)
            loadState = .loaded
        } catch {
            if snapshot == nil {
                loadState = .failed(message: L10n.recommendationFetchFailed)
            } else {
                // Keep stale cache visible; the view layer can surface a toast if it wants.
                loadState = .loaded
            }
        }
    }

    private func backgroundRefresh() {
        inFlightFetch?.cancel()
        inFlightFetch = Task { [weak self] in
            guard let self else { return }
            do {
                let fresh = try await self.fetchCSV()
                self.snapshot = fresh
                self.persistSnapshot(fresh)
            } catch {
                // Silent. Stale cache stays visible.
            }
        }
    }

    private func fetchCSV() async throws -> RecommendationsSnapshot {
        let (data, response) = try await URLSession.shared.data(from: csvURL)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw RecommendationsError.fetchFailed
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw RecommendationsError.decodingFailed
        }
        let rows = RecommendationsCSVParser.rows(from: text)
        let sections = RecommendationsSectionBuilder.build(from: rows)
        return RecommendationsSnapshot(fetchedAt: Date(), sections: sections)
    }

    // MARK: - External link parsing

    private func externalURL(for rec: Recommendation) -> URL? {
        guard let raw = rec.otherLinks?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return nil
        }
        let candidates = raw.components(separatedBy: CharacterSet(charactersIn: " ,\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return candidates.compactMap { URL(string: $0) }.first
    }
}
