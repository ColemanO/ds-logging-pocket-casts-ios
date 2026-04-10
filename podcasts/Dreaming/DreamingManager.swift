import Foundation
import PocketCastsDataModel
import PocketCastsUtils

class DreamingManager {
    static let shared = DreamingManager()

    private let keychainKey = "dreamingBearerToken"
    private let statusDefaultsKey = "DreamingEpisodeLogStatus"

    enum LogStatus: String {
        case pending
        case success
        case failure
    }

    struct ExternalTimeEntry {
        let id: String
        let type: String
        let date: String
        let timeSeconds: Double
        let description: String
    }

    struct DayWatchedTimeEntry {
        let date: String
        let timeSeconds: Double
        let goalReached: Bool
    }

    private(set) var cachedDailyGoalSeconds: Int?
    var cachedTodayWatchedSeconds: Double? {
        guard let times = cachedDayWatchedTimes else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        return times.first { $0.date == today }?.timeSeconds
    }
    private(set) var cachedExternalTimeSeconds: Double?
    private(set) var cachedPlatformWatchTimeSeconds: Double?
    private(set) var cachedTotalInputSeconds: Double?
    private(set) var cachedExternalTimes: [ExternalTimeEntry]?
    private(set) var cachedDayWatchedTimes: [DayWatchedTimeEntry]?

    private init() {}

    // MARK: - Token Management

    var hasToken: Bool {
        getToken() != nil
    }

    func getToken() -> String? {
        try? KeychainHelper.string(for: keychainKey)
    }

    @discardableResult
    func saveToken(_ token: String) -> Bool {
        let result = KeychainHelper.save(string: token, key: keychainKey, accessibility: kSecAttrAccessibleAfterFirstUnlock)
        if result {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Constants.Notifications.dreamingTokenChanged, object: nil)
            }
        }
        return result
    }

    @discardableResult
    func removeToken() -> Bool {
        let result = KeychainHelper.removeKey(keychainKey)
        clearProgressCache()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Constants.Notifications.dreamingTokenChanged, object: nil)
        }
        return result
    }

    // MARK: - Episode Status Tracking

    func logStatus(for episodeUuid: String) -> LogStatus? {
        guard let dict = UserDefaults.standard.dictionary(forKey: statusDefaultsKey),
              let rawValue = dict[episodeUuid] as? String else {
            return nil
        }
        return LogStatus(rawValue: rawValue)
    }

    private func setLogStatus(_ status: LogStatus, for episodeUuid: String) {
        var dict = UserDefaults.standard.dictionary(forKey: statusDefaultsKey) ?? [:]
        dict[episodeUuid] = status.rawValue
        UserDefaults.standard.set(dict, forKey: statusDefaultsKey)

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Constants.Notifications.dreamingLogStatusChanged, object: episodeUuid)
        }
    }

    // MARK: - API Logging

    func logEpisodeCompletions(episodes: [BaseEpisode]) {
        guard hasToken else { return }

        if episodes.count == 1, let episode = episodes.first {
            let podcastTitle: String?
            if let ep = episode as? Episode {
                podcastTitle = DataManager.sharedManager.findPodcast(uuid: ep.podcastUuid)?.title
            } else {
                podcastTitle = nil
            }
            logEpisodeCompletion(episode: episode, podcastTitle: podcastTitle)
            return
        }

        // Group episodes by podcast UUID
        var grouped: [String: [BaseEpisode]] = [:]
        for episode in episodes {
            let key = (episode as? Episode)?.podcastUuid ?? "user-episodes"
            grouped[key, default: []].append(episode)
        }

        for (podcastUuid, groupEpisodes) in grouped {
            let podcastTitle: String?
            if podcastUuid != "user-episodes" {
                podcastTitle = DataManager.sharedManager.findPodcast(uuid: podcastUuid)?.title
            } else {
                podcastTitle = nil
            }

            let totalDuration = groupEpisodes.reduce(0.0) { $0 + $1.duration }

            // Build episode number list for the description
            let episodeNumbers = groupEpisodes.compactMap { ep -> Int64? in
                guard let episode = ep as? Episode, episode.episodeNumber > 0 else { return nil }
                return episode.episodeNumber
            }.sorted()

            var description = podcastTitle ?? "Unknown Podcast"
            if !episodeNumbers.isEmpty {
                description += " - Eps \(formatEpisodeNumbers(episodeNumbers))"
            }

            // Use the first episode's UUID as the tracking key for the group
            guard let firstEpisode = groupEpisodes.first else { continue }
            logGroupCompletion(episodeUuid: firstEpisode.uuid, totalDuration: totalDuration, description: description)
        }
    }

    private func formatEpisodeNumbers(_ numbers: [Int64]) -> String {
        guard !numbers.isEmpty else { return "" }

        var ranges: [String] = []
        var rangeStart = numbers[0]
        var rangeEnd = numbers[0]

        for i in 1..<numbers.count {
            if numbers[i] == rangeEnd + 1 {
                rangeEnd = numbers[i]
            } else {
                ranges.append(rangeStart == rangeEnd ? "\(rangeStart)" : "\(rangeStart)-\(rangeEnd)")
                rangeStart = numbers[i]
                rangeEnd = numbers[i]
            }
        }
        ranges.append(rangeStart == rangeEnd ? "\(rangeStart)" : "\(rangeStart)-\(rangeEnd)")

        return ranges.joined(separator: ", ")
    }

    private func logGroupCompletion(episodeUuid: String, totalDuration: Double, description: String) {
        guard let token = getToken() else { return }

        setLogStatus(.pending, for: episodeUuid)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())

        let timestamp = Int(Date().timeIntervalSince1970)
        let idempotencyKey = UUID().uuidString

        let body: [String: Any] = [
            "id": "\(episodeUuid)-\(timestamp)",
            "timeSeconds": totalDuration,
            "description": description,
            "type": "listening",
            "date": dateString,
            "idempotencyKey": idempotencyKey,
            "externalVideoUrl": ""
        ]

        guard let url = URL(string: "https://app.dreaming.com/.netlify/functions/externalTime?language=es"),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            FileLog.shared.addMessage("Dreaming: Failed to create request")
            setLogStatus(.failure, for: episodeUuid)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error = error {
                FileLog.shared.addMessage("Dreaming: Failed to log episode - \(error.localizedDescription)")
                self?.setLogStatus(.failure, for: episodeUuid)
                return
            }

            if let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) {
                FileLog.shared.addMessage("Dreaming: Successfully logged episode \(episodeUuid)")
                self?.setLogStatus(.success, for: episodeUuid)
            } else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                FileLog.shared.addMessage("Dreaming: Failed to log episode, status code: \(statusCode)")
                self?.setLogStatus(.failure, for: episodeUuid)
            }
        }.resume()
    }

    // MARK: - Progress Data

    func fetchDailyGoal(completion: @escaping (Int?) -> Void) {
        guard let token = getToken() else {
            completion(nil)
            return
        }

        let timezoneOffset = TimeZone.current.secondsFromGMT() / 3600
        guard let url = URL(string: "https://app.dreaming.com/.netlify/functions/user?timezone=\(timezoneOffset)") else {
            FileLog.shared.addMessage("Dreaming: Failed to create daily goal URL")
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                FileLog.shared.addMessage("Dreaming: Failed to fetch daily goal - \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let user = json["user"] as? [String: Any],
                  let dailyGoalSeconds = user["dailyGoalSeconds"] as? Int else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                FileLog.shared.addMessage("Dreaming: Failed to parse daily goal, status: \(statusCode)")
                completion(nil)
                return
            }

            self?.cachedDailyGoalSeconds = dailyGoalSeconds

            // Parse external time summary
            var externalTime: Double = 0
            if let externalTimeSummary = user["externalTimeSummary"] as? [String: Any],
               let es = externalTimeSummary["es"] as? [String: Any],
               let timeSeconds = es["timeSeconds"] as? Double {
                externalTime = timeSeconds
            }
            self?.cachedExternalTimeSeconds = externalTime

            // Parse platform watch time
            var platformTime: Double = 0
            if let cumulativeWatchTimes = user["cumulativeWatchTimes"] as? [String: Any],
               let es = cumulativeWatchTimes["es"] as? Double {
                platformTime = es
            }
            self?.cachedPlatformWatchTimeSeconds = platformTime

            self?.cachedTotalInputSeconds = externalTime + platformTime

            completion(dailyGoalSeconds)
        }.resume()
    }

    func fetchTodayWatchedTime(completion: @escaping (Double?) -> Void) {
        guard let token = getToken() else {
            completion(nil)
            return
        }

        guard let url = URL(string: "https://app.dreaming.com/.netlify/functions/dayWatchedTime?language=es") else {
            FileLog.shared.addMessage("Dreaming: Failed to create watched time URL")
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: Date())

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                FileLog.shared.addMessage("Dreaming: Failed to fetch watched time - \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let data = data,
                  let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                FileLog.shared.addMessage("Dreaming: Failed to parse watched time, status: \(statusCode)")
                completion(nil)
                return
            }

            self?.cachedDayWatchedTimes = entries.compactMap { dict -> DayWatchedTimeEntry? in
                guard let date = dict["date"] as? String,
                      let timeSeconds = dict["timeSeconds"] as? Double else {
                    return nil
                }
                let goalReached = dict["goalReached"] as? Bool ?? false
                return DayWatchedTimeEntry(date: date, timeSeconds: timeSeconds, goalReached: goalReached)
            }

            let todayEntry = entries.first { ($0["date"] as? String) == todayString }
            let watchedSeconds = (todayEntry?["timeSeconds"] as? Double) ?? 0
            completion(watchedSeconds)
        }.resume()
    }

    func fetchExternalTimes(completion: @escaping ([ExternalTimeEntry]?) -> Void) {
        guard let token = getToken() else {
            completion(nil)
            return
        }

        guard let url = URL(string: "https://app.dreaming.com/.netlify/functions/externalTime?language=es") else {
            FileLog.shared.addMessage("Dreaming: Failed to create external times URL")
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                FileLog.shared.addMessage("Dreaming: Failed to fetch external times - \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let externalTimes = json["externalTimes"] as? [[String: Any]] else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                FileLog.shared.addMessage("Dreaming: Failed to parse external times, status: \(statusCode)")
                completion(nil)
                return
            }

            let entries = externalTimes.compactMap { dict -> ExternalTimeEntry? in
                guard let id = dict["id"] as? String,
                      let type = dict["type"] as? String,
                      let date = dict["date"] as? String,
                      let timeSeconds = dict["timeSeconds"] as? Double,
                      let description = dict["description"] as? String else {
                    return nil
                }
                return ExternalTimeEntry(id: id, type: type, date: date, timeSeconds: timeSeconds, description: description)
            }

            self?.cachedExternalTimes = entries
            completion(entries)
        }.resume()
    }

    func refreshProgressData(completion: @escaping () -> Void) {
        let group = DispatchGroup()

        group.enter()
        fetchDailyGoal { _ in
            group.leave()
        }

        group.enter()
        fetchTodayWatchedTime { _ in
            group.leave()
        }

        group.enter()
        fetchExternalTimes { _ in
            group.leave()
        }

        group.notify(queue: .main) {
            completion()
        }
    }

    func clearProgressCache() {
        cachedDailyGoalSeconds = nil
        cachedExternalTimeSeconds = nil
        cachedPlatformWatchTimeSeconds = nil
        cachedTotalInputSeconds = nil
        cachedExternalTimes = nil
        cachedDayWatchedTimes = nil
    }

    // MARK: - Single Episode Logging

    func logEpisodeCompletion(episode: BaseEpisode, podcastTitle: String?) {
        guard let token = getToken() else {
            FileLog.shared.addMessage("Dreaming: No token configured, skipping log")
            return
        }

        let episodeUuid = episode.uuid
        let duration = episode.duration
        var description = podcastTitle ?? "Unknown Podcast"
        if let ep = episode as? Episode, ep.episodeNumber > 0 {
            description += " - Ep \(ep.episodeNumber)"
        }

        setLogStatus(.pending, for: episodeUuid)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())

        let timestamp = Int(Date().timeIntervalSince1970)
        let idempotencyKey = UUID().uuidString

        let body: [String: Any] = [
            "id": "\(episodeUuid)-\(timestamp)",
            "timeSeconds": duration,
            "description": description,
            "type": "listening",
            "date": dateString,
            "idempotencyKey": idempotencyKey,
            "externalVideoUrl": ""
        ]

        guard let url = URL(string: "https://app.dreaming.com/.netlify/functions/externalTime?language=es"),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            FileLog.shared.addMessage("Dreaming: Failed to create request")
            setLogStatus(.failure, for: episodeUuid)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error = error {
                FileLog.shared.addMessage("Dreaming: Failed to log episode - \(error.localizedDescription)")
                self?.setLogStatus(.failure, for: episodeUuid)
                return
            }

            if let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) {
                FileLog.shared.addMessage("Dreaming: Successfully logged episode \(episodeUuid)")
                self?.setLogStatus(.success, for: episodeUuid)
            } else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                FileLog.shared.addMessage("Dreaming: Failed to log episode, status code: \(statusCode)")
                self?.setLogStatus(.failure, for: episodeUuid)
            }
        }.resume()
    }
}
