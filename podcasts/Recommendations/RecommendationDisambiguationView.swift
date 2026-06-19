import PocketCastsServer
import SwiftUI

struct RecommendationDisambiguationPayload: Identifiable, Equatable {
    let id = UUID()
    let rec: Recommendation
    let results: [PodcastFolderSearchResult]
    let externalURL: URL?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

struct RecommendationDisambiguationView: View {
    @EnvironmentObject var theme: Theme
    @Environment(\.dismiss) private var dismiss

    let payload: RecommendationDisambiguationPayload
    let onPodcastChosen: (String) -> Void
    let onExternalChosen: (URL) -> Void

    var body: some View {
        NavigationView {
            ZStack {
                theme.primaryUi01.ignoresSafeArea()
                List {
                    Section {
                        Text(payload.rec.title)
                            .font(.headline)
                            .foregroundColor(theme.primaryText01)
                            .listRowBackground(theme.primaryUi02)
                    }

                    if !payload.results.isEmpty {
                        Section {
                            ForEach(payload.results.prefix(5), id: \.uuid) { result in
                                Button(action: { choosePodcast(uuid: result.uuid) }) {
                                    HStack(spacing: 12) {
                                        DisambiguationArtwork(uuid: result.uuid)
                                            .frame(width: 44, height: 44)
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(result.title ?? "")
                                                .font(.body)
                                                .foregroundColor(theme.primaryText01)
                                                .lineLimit(1)
                                            if let author = result.author, !author.isEmpty {
                                                Text(author)
                                                    .font(.caption)
                                                    .foregroundColor(theme.primaryText02)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                    }
                                }
                                .listRowBackground(theme.primaryUi02)
                            }
                        }
                    }

                    if let extURL = payload.externalURL {
                        Section {
                            Button(action: { chooseExternal(url: extURL) }) {
                                HStack {
                                    Image(systemName: "arrow.up.right.square")
                                        .foregroundColor(theme.primaryInteractive01)
                                    Text(L10n.recommendationOpenExternal)
                                        .foregroundColor(theme.primaryInteractive01)
                                    Spacer()
                                }
                            }
                            .listRowBackground(theme.primaryUi02)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(L10n.recommendationChoosePodcast)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                        .foregroundColor(theme.primaryInteractive01)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func choosePodcast(uuid: String) {
        onPodcastChosen(uuid)
        dismiss()
    }

    private func chooseExternal(url: URL) {
        onExternalChosen(url)
        dismiss()
    }
}

private struct DisambiguationArtwork: UIViewRepresentable {
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
