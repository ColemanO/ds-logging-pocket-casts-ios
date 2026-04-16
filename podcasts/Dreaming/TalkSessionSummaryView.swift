import SwiftUI

struct TalkSessionSummaryView: View {
    enum TalkType: String, CaseIterable {
        case crosstalk
        case output
    }

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
                Section(header: Text(L10n.talkDuration)) {
                    HStack {
                        TextField("min", text: $minutes)
                            .keyboardType(.numberPad)
                            .frame(width: 60)
                        Text("m")
                            .foregroundColor(.secondary)
                        TextField("sec", text: $seconds)
                            .keyboardType(.numberPad)
                            .frame(width: 60)
                        Text("s")
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text(L10n.talkType)) {
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
                }

                Section(header: Text(L10n.talkDescription)) {
                    TextField(L10n.talkDescription, text: $descriptionText)
                }

                Section(header: Text(L10n.talkDate)) {
                    DatePicker(L10n.talkDate, selection: $date, displayedComponents: .date)
                }

                Section {
                    Button(action: logSession) {
                        if isLogging {
                            HStack {
                                ProgressView()
                                Text(L10n.talkLog)
                            }
                        } else {
                            Text(L10n.talkLog)
                        }
                    }
                    .disabled(isLogging || totalSeconds <= 0)

                    Button(L10n.talkDiscard, role: .destructive) {
                        dismiss()
                    }
                    .disabled(isLogging)
                }
            }
            .navigationTitle(L10n.talkLogSession)
            .alert(L10n.talkFailedToLog, isPresented: $showError) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func logSession() {
        isLogging = true
        DreamingManager.shared.logTalkSession(
            timeSeconds: totalSeconds,
            description: descriptionText,
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
