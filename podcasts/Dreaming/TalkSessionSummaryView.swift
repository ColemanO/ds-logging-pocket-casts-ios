import SwiftUI

struct TalkSessionSummaryView: View {
    private enum PrimaryType: String, CaseIterable, Identifiable {
        case watching
        case talking
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .watching: return L10n.primaryTypeWatching
            case .talking:  return L10n.primaryTypeTalking
            }
        }
    }

    private enum Field: Hashable {
        case watchingSource, watchingTitle, talkingDescription
    }

    @EnvironmentObject var theme: Theme

    @FocusState private var focusedField: Field?
    @State private var minutes: String
    @State private var seconds: String
    @State private var primaryType: PrimaryType
    @State private var subType: TalkingSubType
    @State private var watchingSource: String
    @State private var watchingTitle: String
    @State private var talkingUserDescription: String
    @State private var date: Date = Date()
    @State private var isLogging: Bool = false
    @State private var showError: Bool = false
    @State private var youtubeUrl: String = ""
    @State private var isFetchingYoutube: Bool = false

    @Environment(\.dismiss) private var dismiss

    private let onLogged: (() -> Void)?

    init(durationSeconds: Double? = nil, initialKind: ManualEntryKind? = nil, onLogged: (() -> Void)? = nil) {
        self.onLogged = onLogged

        if let duration = durationSeconds {
            let totalSeconds = Int(duration)
            _minutes = State(initialValue: "\(totalSeconds / 60)")
            _seconds = State(initialValue: "\(totalSeconds % 60)")
        } else {
            _minutes = State(initialValue: "")
            _seconds = State(initialValue: "0")
        }

        // Populate type-specific fields from initialKind if provided.
        switch initialKind {
        case .watching(let source, let title):
            _primaryType = State(initialValue: .watching)
            _subType = State(initialValue: .talking)
            _watchingSource = State(initialValue: source)
            _watchingTitle = State(initialValue: title)
            _talkingUserDescription = State(initialValue: "")
        case .talking(let subType, let userDescription):
            _primaryType = State(initialValue: .talking)
            _subType = State(initialValue: subType)
            _watchingSource = State(initialValue: "")
            _watchingTitle = State(initialValue: "")
            _talkingUserDescription = State(initialValue: userDescription ?? "")
        case .none:
            _primaryType = State(initialValue: .talking)
            _subType = State(initialValue: .talking)
            _watchingSource = State(initialValue: "")
            _watchingTitle = State(initialValue: "")
            _talkingUserDescription = State(initialValue: "")
        }
    }

    private var totalSeconds: Double {
        let m = Double(minutes) ?? 0
        let s = Double(seconds) ?? 0
        return m * 60 + s
    }

    private var kind: ManualEntryKind {
        switch primaryType {
        case .watching:
            return .watching(source: watchingSource, title: watchingTitle)
        case .talking:
            let trimmed = talkingUserDescription.trimmingCharacters(in: .whitespaces)
            return .talking(subType: subType, userDescription: trimmed.isEmpty ? nil : trimmed)
        }
    }

    var body: some View {
        NavigationView {
            Form {
                durationSection
                typeSection
                conditionalFieldsSection
                dateSection
                buttonsSection
            }
            .scrollContentBackground(.hidden)
            .background(theme.primaryUi01)
            .navigationTitle(L10n.talkLogSession)
            .navigationBarTitleDisplayMode(.inline)
            .alert(L10n.talkFailedToLog, isPresented: $showError) {
                Button("OK", role: .cancel) {}
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Sections

    private var durationSection: some View {
        Section {
            HStack {
                TextField("min", text: $minutes)
                    .keyboardType(.numberPad)
                    .frame(width: 60)
                    .foregroundColor(theme.primaryText01)
                Text("m")
                    .foregroundColor(theme.primaryText02)
                TextField("sec", text: $seconds)
                    .keyboardType(.numberPad)
                    .frame(width: 60)
                    .foregroundColor(theme.primaryText01)
                Text("s")
                    .foregroundColor(theme.primaryText02)
            }
        } header: {
            Text(L10n.talkDuration)
                .foregroundColor(theme.primaryText02)
        }
        .listRowBackground(theme.primaryUi02)
    }

    private var typeSection: some View {
        Section {
            Picker(L10n.entryType, selection: $primaryType) {
                ForEach(PrimaryType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text(L10n.entryType)
                .foregroundColor(theme.primaryText02)
        }
        .listRowBackground(theme.primaryUi02)
    }

    private func suggestions(from pool: [String], matching query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return Array(pool
            .filter { $0.localizedCaseInsensitiveContains(q) && $0.lowercased() != q.lowercased() }
            .prefix(4))
    }

    @ViewBuilder
    private var conditionalFieldsSection: some View {
        switch primaryType {
        case .watching:
            Section {
                HStack {
                    TextField("YouTube URL", text: $youtubeUrl)
                        .foregroundColor(theme.primaryText01)
                        .autocorrectionDisabled()
                        .onChange(of: youtubeUrl) { newValue in
                            fetchYouTubeDetailsIfNeeded(url: newValue)
                        }
                    if isFetchingYoutube {
                        ProgressView()
                            .tint(theme.primaryInteractive01)
                    }
                }
            } header: {
                Text("YouTube")
                    .foregroundColor(theme.primaryText02)
            }
            .listRowBackground(theme.primaryUi02)

            Section {
                TextField(L10n.watchingSource, text: $watchingSource)
                    .foregroundColor(theme.primaryText01)
                    .focused($focusedField, equals: .watchingSource)
                if focusedField == .watchingSource {
                    ForEach(suggestions(from: DreamingManager.shared.suggestedWatchingSources, matching: watchingSource), id: \.self) { s in
                        Button(s) {
                            watchingSource = s
                            focusedField = nil
                        }
                        .foregroundColor(theme.primaryInteractive01)
                    }
                }
                TextField(L10n.watchingTitle, text: $watchingTitle)
                    .foregroundColor(theme.primaryText01)
                    .focused($focusedField, equals: .watchingTitle)
                if focusedField == .watchingTitle {
                    ForEach(suggestions(from: DreamingManager.shared.suggestedWatchingTitles, matching: watchingTitle), id: \.self) { s in
                        Button(s) {
                            watchingTitle = s
                            focusedField = nil
                        }
                        .foregroundColor(theme.primaryInteractive01)
                    }
                }
            } header: {
                Text(L10n.primaryTypeWatching)
                    .foregroundColor(theme.primaryText02)
            }
            .listRowBackground(theme.primaryUi02)

        case .talking:
            Section {
                Picker(L10n.talkingSubType, selection: $subType) {
                    Text(L10n.talkingSubTypeTalking).tag(TalkingSubType.talking)
                    Text(L10n.talkTypeCrosstalk).tag(TalkingSubType.crosstalk)
                    Text(L10n.talkingSubTypeReverseCrosstalk).tag(TalkingSubType.reverseCrosstalk)
                }
                .pickerStyle(.segmented)

                TextField(L10n.talkingDescription, text: $talkingUserDescription)
                    .foregroundColor(theme.primaryText01)
                    .focused($focusedField, equals: .talkingDescription)
                if focusedField == .talkingDescription {
                    ForEach(suggestions(from: DreamingManager.shared.suggestedTalkingDescriptions, matching: talkingUserDescription), id: \.self) { s in
                        Button(s) {
                            talkingUserDescription = s
                            focusedField = nil
                        }
                        .foregroundColor(theme.primaryInteractive01)
                    }
                }
            } header: {
                Text(L10n.talkingSubType)
                    .foregroundColor(theme.primaryText02)
            }
            .listRowBackground(theme.primaryUi02)
        }
    }

    private var dateSection: some View {
        Section {
            DatePicker(L10n.talkDate, selection: $date, displayedComponents: .date)
                .foregroundColor(theme.primaryText01)
        } header: {
            Text(L10n.talkDate)
                .foregroundColor(theme.primaryText02)
        }
        .listRowBackground(theme.primaryUi02)
    }

    private var buttonsSection: some View {
        Section {
            Button(action: logSession) {
                HStack {
                    if isLogging {
                        ProgressView()
                            .tint(theme.primaryInteractive01)
                    }
                    Text(L10n.talkLog)
                        .foregroundColor(theme.primaryInteractive01)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(isLogging || totalSeconds <= 0 || kind.encodedDescription.isEmpty)

            Button(action: { dismiss() }) {
                Text(L10n.talkDiscard)
                    .foregroundColor(theme.support05)
                    .frame(maxWidth: .infinity)
            }
            .disabled(isLogging)
        }
        .listRowBackground(theme.primaryUi02)
    }

    // MARK: - YouTube Auto-fill

    private func fetchYouTubeDetailsIfNeeded(url: String) {
        guard let videoId = YouTubeManager.extractVideoId(from: url),
              let apiKey = DreamingManager.shared.getYouTubeApiKey() else { return }

        isFetchingYoutube = true
        YouTubeManager.fetchVideoDetails(videoId: videoId, apiKey: apiKey) { details in
            DispatchQueue.main.async {
                isFetchingYoutube = false
                guard let details = details else { return }
                if watchingSource.trimmingCharacters(in: .whitespaces).isEmpty {
                    watchingSource = details.channelTitle
                }
                if watchingTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                    watchingTitle = details.title
                }
                if minutes.trimmingCharacters(in: .whitespaces).isEmpty {
                    let total = Int(details.durationSeconds)
                    minutes = "\(total / 60)"
                    seconds = "\(total % 60)"
                }
            }
        }
    }

    // MARK: - Submission

    private func logSession() {
        isLogging = true
        let videoUrl = youtubeUrl.trimmingCharacters(in: .whitespaces).isEmpty ? nil : youtubeUrl.trimmingCharacters(in: .whitespaces)
        DreamingManager.shared.logExternalEntry(
            type: kind.apiType,
            description: kind.encodedDescription,
            timeSeconds: totalSeconds,
            date: date,
            videoUrl: videoUrl
        ) { success in
            isLogging = false
            if success {
                onLogged?()
                dismiss()
            } else {
                showError = true
            }
        }
    }
}
