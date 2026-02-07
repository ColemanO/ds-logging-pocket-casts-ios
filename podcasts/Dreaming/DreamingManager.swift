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
        KeychainHelper.save(string: token, key: keychainKey, accessibility: kSecAttrAccessibleAfterFirstUnlock)
    }

    @discardableResult
    func removeToken() -> Bool {
        KeychainHelper.removeKey(keychainKey)
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
