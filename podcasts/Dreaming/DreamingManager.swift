import Foundation
import PocketCastsDataModel
import PocketCastsUtils

class DreamingManager {
    static let shared = DreamingManager()

    private let keychainKey = "dreamingBearerToken"
    private let statusDefaultsKey = "DreamingEpisodeLogStatus"
    private let errorDefaultsKey = "DreamingEpisodeLogErrors"

    enum LogStatus: String {
        case pending
        case success
        case failure
    }

    struct LogError {
        let statusCode: Int
        let message: String
        let date: Date
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

    func logError(for episodeUuid: String) -> LogError? {
        guard let dict = UserDefaults.standard.dictionary(forKey: errorDefaultsKey),
              let entry = dict[episodeUuid] as? [String: Any],
              let statusCode = entry["statusCode"] as? Int,
              let message = entry["message"] as? String,
              let timestamp = entry["timestamp"] as? Double else {
            return nil
        }
        return LogError(statusCode: statusCode, message: message, date: Date(timeIntervalSince1970: timestamp))
    }

    private func setLogError(_ error: LogError?, for episodeUuid: String) {
        var dict = UserDefaults.standard.dictionary(forKey: errorDefaultsKey) ?? [:]
        if let error = error {
            dict[episodeUuid] = [
                "statusCode": error.statusCode,
                "message": error.message,
                "timestamp": error.date.timeIntervalSince1970
            ]
        } else {
            dict.removeValue(forKey: episodeUuid)
        }
        UserDefaults.standard.set(dict, forKey: errorDefaultsKey)
    }

    // MARK: - API Logging

    func logEpisodeCompletions(episodes: [BaseEpisode]) {
        guard hasToken else { return }

        if episodes.count == 1, let episode = episodes.first {
            let podcastTitle: String?
            if let ep = episode as? Episode {
                podcastTitle = ep.parentPodcast()?.title
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
                podcastTitle = DataManager.sharedManager.findPodcast(uuid: podcastUuid, includeUnsubscribed: true)?.title
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
            "today": dateString,
            "idempotencyKey": idempotencyKey,
            "externalVideoUrl": ""
        ]

        guard let url = URL(string: "https://app.dreaming.com/.netlify/functions/externalTime?language=es"),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            FileLog.shared.addMessage("Dreaming: Failed to create request")
            setLogError(LogError(statusCode: -1, message: "Failed to create request", date: Date()), for: episodeUuid)
            setLogStatus(.failure, for: episodeUuid)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                FileLog.shared.addMessage("Dreaming: Failed to log episode - \(error.localizedDescription)")
                self?.setLogError(LogError(statusCode: -1, message: error.localizedDescription, date: Date()), for: episodeUuid)
                self?.setLogStatus(.failure, for: episodeUuid)
                return
            }

            if let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) {
                FileLog.shared.addMessage("Dreaming: Successfully logged episode \(episodeUuid)")
                self?.setLogError(nil, for: episodeUuid)
                self?.setLogStatus(.success, for: episodeUuid)
            } else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                FileLog.shared.addMessage("Dreaming: Failed to log episode, status code: \(statusCode)")
                let message = body.isEmpty ? "HTTP \(statusCode)" : body
                self?.setLogError(LogError(statusCode: statusCode, message: message, date: Date()), for: episodeUuid)
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

    // MARK: - Milestone Predictions

    enum VelocityTrend {
        case increasing
        case decreasing
        case stable
    }

    struct VelocityInfo {
        let currentHours: Double
        let velocity: Double
        let trend: VelocityTrend
    }

    struct MilestonePrediction {
        let milestoneLevel: Int
        let milestoneHours: Double
        let estimatedDaysRemaining: Int
        let estimatedDate: Date
        let optimisticDate: Date
        let pessimisticDate: Date
    }

    private static let milestoneThresholds: [(level: Int, hours: Double)] = [
        (1, 0), (2, 50), (3, 150), (4, 300), (5, 600), (6, 1000), (7, 1500)
    ]

    func calculateMilestonePredictions() -> (VelocityInfo, [MilestonePrediction])? {
        guard let dayTimes = cachedDayWatchedTimes, !dayTimes.isEmpty else { return nil }

        // Build current total hours
        var initialSeconds = 0.0
        if let externalTimes = cachedExternalTimes {
            initialSeconds = externalTimes
                .filter { $0.type == "initial" }
                .reduce(0.0) { $0 + $1.timeSeconds }
        }
        let totalDaySeconds = dayTimes.reduce(0.0) { $0 + $1.timeSeconds }
        let currentHours = (initialSeconds + totalDaySeconds) / 3600.0

        // Build last 30 days of daily hours (filling gaps with zero)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        var hoursByDate: [String: Double] = [:]
        for entry in dayTimes {
            hoursByDate[entry.date, default: 0] += entry.timeSeconds / 3600.0
        }

        let today = Date()
        let cal = Calendar.current
        var last30: [Double] = []
        for i in 0..<30 {
            let date = cal.date(byAdding: .day, value: -i, to: today)!
            let key = formatter.string(from: date)
            last30.append(hoursByDate[key] ?? 0)
        }
        // last30[0] = today, last30[29] = 29 days ago

        // Weighted velocity: exponential decay, day 0 weight=1.0, day 29 weight≈0.25
        let decayRate = log(4.0) / 29.0 // so exp(-decayRate * 29) ≈ 0.25
        var weightedSum = 0.0
        var weightSum = 0.0
        for i in 0..<30 {
            let weight = exp(-decayRate * Double(i))
            weightedSum += last30[i] * weight
            weightSum += weight
        }
        let velocity = weightedSum / weightSum

        guard velocity >= 0.01 else { return nil }

        // Standard deviation of the 30 daily values
        let mean = last30.reduce(0, +) / 30.0
        let variance = last30.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / 30.0
        let stddev = sqrt(variance)

        let optimisticVelocity = velocity + stddev
        let pessimisticVelocity = max(velocity - stddev, 0.01)

        // Trend: weighted avg of days 0-14 vs days 15-29
        var recentWeighted = 0.0, recentWeightSum = 0.0
        var olderWeighted = 0.0, olderWeightSum = 0.0
        for i in 0..<15 {
            let weight = exp(-decayRate * Double(i))
            recentWeighted += last30[i] * weight
            recentWeightSum += weight
        }
        for i in 15..<30 {
            let weight = exp(-decayRate * Double(i))
            olderWeighted += last30[i] * weight
            olderWeightSum += weight
        }
        let recentAvg = recentWeighted / recentWeightSum
        let olderAvg = olderWeighted / olderWeightSum

        let trend: VelocityTrend
        if olderAvg < 0.01 {
            trend = recentAvg > 0.01 ? .increasing : .stable
        } else {
            let ratio = recentAvg / olderAvg
            if ratio > 1.1 {
                trend = .increasing
            } else if ratio < 0.9 {
                trend = .decreasing
            } else {
                trend = .stable
            }
        }

        let velocityInfo = VelocityInfo(currentHours: currentHours, velocity: velocity, trend: trend)

        // Predictions for all remaining milestones
        var predictions: [MilestonePrediction] = []
        for threshold in Self.milestoneThresholds {
            guard threshold.hours > currentHours else { continue }

            let remaining = threshold.hours - currentHours
            let estDays = Int(ceil(remaining / velocity))
            let optDays = Int(ceil(remaining / optimisticVelocity))
            let pesDays = Int(ceil(remaining / pessimisticVelocity))

            predictions.append(MilestonePrediction(
                milestoneLevel: threshold.level,
                milestoneHours: threshold.hours,
                estimatedDaysRemaining: estDays,
                estimatedDate: cal.date(byAdding: .day, value: estDays, to: today)!,
                optimisticDate: cal.date(byAdding: .day, value: optDays, to: today)!,
                pessimisticDate: cal.date(byAdding: .day, value: pesDays, to: today)!
            ))
        }

        guard !predictions.isEmpty else { return nil }
        return (velocityInfo, predictions)
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
            "today": dateString,
            "idempotencyKey": idempotencyKey,
            "externalVideoUrl": ""
        ]

        guard let url = URL(string: "https://app.dreaming.com/.netlify/functions/externalTime?language=es"),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            FileLog.shared.addMessage("Dreaming: Failed to create request")
            setLogError(LogError(statusCode: -1, message: "Failed to create request", date: Date()), for: episodeUuid)
            setLogStatus(.failure, for: episodeUuid)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                FileLog.shared.addMessage("Dreaming: Failed to log episode - \(error.localizedDescription)")
                self?.setLogError(LogError(statusCode: -1, message: error.localizedDescription, date: Date()), for: episodeUuid)
                self?.setLogStatus(.failure, for: episodeUuid)
                return
            }

            if let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) {
                FileLog.shared.addMessage("Dreaming: Successfully logged episode \(episodeUuid)")
                self?.setLogError(nil, for: episodeUuid)
                self?.setLogStatus(.success, for: episodeUuid)
            } else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                FileLog.shared.addMessage("Dreaming: Failed to log episode, status code: \(statusCode)")
                let message = body.isEmpty ? "HTTP \(statusCode)" : body
                self?.setLogError(LogError(statusCode: statusCode, message: message, date: Date()), for: episodeUuid)
                self?.setLogStatus(.failure, for: episodeUuid)
            }
        }.resume()
    }

    // MARK: - Manual Entry Logging

    func logExternalEntry(type: String, description: String, timeSeconds: Double, date: Date, completion: @escaping (Bool) -> Void) {
        guard let token = getToken() else {
            FileLog.shared.addMessage("Dreaming: No token configured, skipping external entry log")
            DispatchQueue.main.async { completion(false) }
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        let todayString = dateFormatter.string(from: Date())

        let timestamp = Int(Date().timeIntervalSince1970)
        let idempotencyKey = UUID().uuidString

        let body: [String: Any] = [
            "id": "\(type)-\(timestamp)",
            "timeSeconds": timeSeconds,
            "description": description,
            "type": type,
            "date": dateString,
            "today": todayString,
            "idempotencyKey": idempotencyKey,
            "externalVideoUrl": ""
        ]

        guard let url = URL(string: "https://app.dreaming.com/.netlify/functions/externalTime?language=es"),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            FileLog.shared.addMessage("Dreaming: Failed to create external entry request")
            DispatchQueue.main.async { completion(false) }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                FileLog.shared.addMessage("Dreaming: Failed to log external entry - \(error.localizedDescription)")
                DispatchQueue.main.async { completion(false) }
                return
            }

            if let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) {
                FileLog.shared.addMessage("Dreaming: Successfully logged external entry (\(type))")
                DispatchQueue.main.async { completion(true) }
            } else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                FileLog.shared.addMessage("Dreaming: Failed to log external entry, status code: \(statusCode)")
                DispatchQueue.main.async { completion(false) }
            }
        }.resume()
    }
}
