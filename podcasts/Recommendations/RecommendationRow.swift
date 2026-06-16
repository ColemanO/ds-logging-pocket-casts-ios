import SwiftUI

struct RecommendationRow: View {
    @EnvironmentObject var theme: Theme
    let rec: Recommendation

    @State private var matchedUUID: String?

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
        .task { matchedUUID = resolveCachedUUID() }
    }

    @ViewBuilder
    private var artwork: some View {
        if let uuid = matchedUUID {
            PodcastArtworkView(uuid: uuid)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.primaryUi02)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "mic.fill")
                        .foregroundColor(theme.primaryText02)
                )
        }
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

    private func resolveCachedUUID() -> String? {
        guard case .podcast(let uuid) = RecommendationsRepository.shared.cachedMatch(for: rec) else {
            return nil
        }
        return uuid
    }
}

/// Bridges UIKit `ImageManager` artwork loading into SwiftUI.
private struct PodcastArtworkView: UIViewRepresentable {
    let uuid: String

    func makeUIView(context _: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        ImageManager.sharedManager.loadImage(podcastUuid: uuid, imageView: view, size: .list, showPlaceHolder: true)
        return view
    }

    func updateUIView(_ uiView: UIImageView, context _: Context) {
        ImageManager.sharedManager.loadImage(podcastUuid: uuid, imageView: uiView, size: .list, showPlaceHolder: true)
    }
}
