import SwiftUI

struct TalkSessionSummaryView: View {
    enum TalkType: String, CaseIterable {
        case crosstalk
        case output
    }

    @EnvironmentObject var theme: Theme

    @State private var minutes: String
    @State private var seconds: String
    @State private var talkType: TalkType = .crosstalk
    @State private var descriptionText: String = L10n.talkCrosstalkSession
    @State private var date: Date = Date()
    @State private var isLogging: Bool = false
    @State private var showError: Bool = false

    @Environment(\.dismiss) private var dismiss

    private let onLogged: (() -> Void)?

    init(durationSeconds: Double? = nil, onLogged: (() -> Void)? = nil) {
        self.onLogged = onLogged
        if let duration = durationSeconds {
            let totalSeconds = Int(duration)
            _minutes = State(initialValue: "\(totalSeconds / 60)")
            _seconds = State(initialValue: "\(totalSeconds % 60)")
        } else {
            _minutes = State(initialValue: "")
            _seconds = State(initialValue: "0")
        }
    }

    private var totalSeconds: Double {
        let m = Double(minutes) ?? 0
        let s = Double(seconds) ?? 0
        return m * 60 + s
    }

    var body: some View {
        NavigationView {
            Form {
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

                Section {
                    Picker(L10n.talkType, selection: $talkType) {
                        Text(L10n.talkTypeCrosstalk).tag(TalkType.crosstalk)
                        Text(L10n.talkTypeOutput).tag(TalkType.output)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: talkType) { newValue in
                        switch newValue {
                        case .crosstalk:
                            descriptionText = L10n.talkCrosstalkSession
                        case .output:
                            descriptionText = L10n.talkOutputSession
                        }
                    }
                } header: {
                    Text(L10n.talkType)
                        .foregroundColor(theme.primaryText02)
                }
                .listRowBackground(theme.primaryUi02)

                Section {
                    TextField(L10n.talkDescription, text: $descriptionText)
                        .foregroundColor(theme.primaryText01)
                } header: {
                    Text(L10n.talkDescription)
                        .foregroundColor(theme.primaryText02)
                }
                .listRowBackground(theme.primaryUi02)

                Section {
                    DatePicker(L10n.talkDate, selection: $date, displayedComponents: .date)
                        .foregroundColor(theme.primaryText01)
                } header: {
                    Text(L10n.talkDate)
                        .foregroundColor(theme.primaryText02)
                }
                .listRowBackground(theme.primaryUi02)

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
                    .disabled(isLogging || totalSeconds <= 0)

                    Button(action: { dismiss() }) {
                        Text(L10n.talkDiscard)
                            .foregroundColor(theme.support05)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(isLogging)
                }
                .listRowBackground(theme.primaryUi02)
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

    private func logSession() {
        isLogging = true
        DreamingManager.shared.logExternalEntry(
            type: "talking",
            description: descriptionText,
            timeSeconds: totalSeconds,
            date: date
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
