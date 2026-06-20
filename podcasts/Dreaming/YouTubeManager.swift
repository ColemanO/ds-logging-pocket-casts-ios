import Foundation

struct YouTubeVideoDetails {
    let title: String
    let channelTitle: String
    let durationSeconds: Double
}

enum YouTubeManager {
    static func extractVideoId(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let host = url.host ?? ""

        // youtu.be/<id>
        if host == "youtu.be" {
            let id = url.pathComponents.dropFirst().first ?? ""
            return id.isEmpty ? nil : id
        }

        // youtube.com/watch?v=<id> or /shorts/<id> or /embed/<id> or /v/<id>
        if host.hasSuffix("youtube.com") {
            if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty {
                return v
            }
            let path = url.pathComponents
            if let idx = path.firstIndex(where: { ["shorts", "embed", "v"].contains($0) }),
               idx + 1 < path.count {
                let id = path[idx + 1]
                return id.isEmpty ? nil : id
            }
        }

        return nil
    }

    static func fetchVideoDetails(
        videoId: String,
        apiKey: String,
        completion: @escaping (YouTubeVideoDetails?) -> Void
    ) {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails"),
            URLQueryItem(name: "id", value: videoId),
            URLQueryItem(name: "key", value: apiKey)
        ]
        guard let url = components.url else {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            guard error == nil, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]],
                  let item = items.first else {
                completion(nil)
                return
            }

            let snippet = item["snippet"] as? [String: Any]
            let contentDetails = item["contentDetails"] as? [String: Any]

            let title = snippet?["title"] as? String ?? ""
            let channelTitle = snippet?["channelTitle"] as? String ?? ""
            let isoDuration = contentDetails?["duration"] as? String ?? ""
            let durationSeconds = parseISO8601Duration(isoDuration)

            completion(YouTubeVideoDetails(title: title, channelTitle: channelTitle, durationSeconds: durationSeconds))
        }.resume()
    }

    // Parses PT#H#M#S into total seconds.
    private static func parseISO8601Duration(_ duration: String) -> Double {
        var seconds: Double = 0
        var current = ""
        for ch in duration {
            if ch.isNumber || ch == "." {
                current.append(ch)
            } else {
                let value = Double(current) ?? 0
                current = ""
                switch ch {
                case "H": seconds += value * 3600
                case "M": seconds += value * 60
                case "S": seconds += value
                default: break
                }
            }
        }
        return seconds
    }
}
