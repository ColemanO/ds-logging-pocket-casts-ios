import SwiftUI

struct RecommendationRow: View {
    @EnvironmentObject var theme: Theme
    let rec: Recommendation

    @State private var thumbnailURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(rec.title)
                    .font(.body)
                    .foregroundColor(theme.primaryText01)
                    .lineLimit(1)
                if let region = rec.region, !region.isEmpty {
                    Text(region)
                        .font(.caption)
                        .foregroundColor(theme.primaryText02)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if rec.mentions > 0 {
                mentionsBadge
            }
        }
        .padding(.vertical, 4)
        .task {
            guard let spotifyURL = rec.spotifyURL else { return }
            thumbnailURL = await SpotifyOEmbedClient.shared.thumbnailURL(for: spotifyURL)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        AsyncImage(url: thumbnailURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "mic.fill")
                    .foregroundColor(theme.primaryText02)
            }
        }
        .frame(width: 44, height: 44)
        .background(theme.primaryUi02)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var mentionsBadge: some View {
        Text("\(rec.mentions)")
            .font(.caption.weight(.semibold))
            .foregroundColor(theme.primaryText01)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(theme.primaryUi02)
            )
            .accessibilityLabel(L10n.recommendationMentionsLabel("\(rec.mentions)"))
    }
}
