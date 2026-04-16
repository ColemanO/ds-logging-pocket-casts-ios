import Combine
import SwiftUI

struct TalkTimerView: View {
    enum TimerState: String {
        case idle
        case running
        case paused
    }

    private enum DefaultsKey {
        static let startTime = "TalkTimerStartTime"
        static let accumulatedSeconds = "TalkTimerAccumulatedSeconds"
        static let state = "TalkTimerState"
    }

    @State private var timerState: TimerState = .idle
    @State private var accumulatedSeconds: Double = 0
    @State private var startTime: Date?
    @State private var displaySeconds: Double = 0
    @State private var showSummary = false
    @State private var summaryDuration: Double?
    @State private var recentSessions: [DreamingManager.ExternalTimeEntry] = []
    @State private var timer: Publishers.Autoconnect<Timer.TimerPublisher>?
    @State private var timerCancellable: AnyCancellable?

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                timerDisplay
                controls
                logManuallyButton
                recentSessionsSection
            }
            .padding()
        }
        .onAppear {
            restoreState()
            loadRecentSessions()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            restoreState()
        }
        .sheet(isPresented: $showSummary) {
            TalkSessionSummaryView(durationSeconds: summaryDuration) {
                loadRecentSessions()
            }
        }
    }

    // MARK: - Timer Display

    private var timerDisplay: some View {
        Text(formatTime(displaySeconds))
            .font(.system(size: 64, weight: .light, design: .monospaced))
            .monospacedDigit()
            .padding(.top, 40)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 40) {
            switch timerState {
            case .idle:
                Button(action: start) {
                    timerButton(label: L10n.talkStart, color: .green)
                }
            case .running:
                Button(action: pause) {
                    timerButton(label: L10n.talkPause, color: .orange)
                }
                Button(action: stop) {
                    timerButton(label: L10n.talkStop, color: .red)
                }
            case .paused:
                Button(action: resume) {
                    timerButton(label: L10n.talkResume, color: .green)
                }
                Button(action: stop) {
                    timerButton(label: L10n.talkStop, color: .red)
                }
            }
        }
    }

    private func timerButton(label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 64, height: 64)
                .overlay(
                    Text(label)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                )
        }
    }

    // MARK: - Log Manually

    private var logManuallyButton: some View {
        Button(action: {
            summaryDuration = nil
            showSummary = true
        }) {
            Text(L10n.talkLogManually)
                .font(.body)
                .foregroundColor(.accentColor)
        }
    }

    // MARK: - Recent Sessions

    private var recentSessionsSection: some View {
        Group {
            if !recentSessions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.talkRecentSessions)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(recentSessions, id: \.id) { session in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.description)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(session.date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(formatDurationShort(session.timeSeconds))
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Timer Actions

    private func start() {
        let now = Date()
        startTime = now
        accumulatedSeconds = 0
        timerState = .running
        displaySeconds = 0
        persistState()
        startTicker()
    }

    private func pause() {
        guard let start = startTime else { return }
        accumulatedSeconds += Date().timeIntervalSince(start)
        startTime = nil
        timerState = .paused
        displaySeconds = accumulatedSeconds
        persistState()
        stopTicker()
    }

    private func resume() {
        startTime = Date()
        timerState = .running
        persistState()
        startTicker()
    }

    private func stop() {
        var finalDuration = accumulatedSeconds
        if let start = startTime {
            finalDuration += Date().timeIntervalSince(start)
        }
        timerState = .idle
        startTime = nil
        accumulatedSeconds = 0
        displaySeconds = 0
        clearPersistedState()
        stopTicker()

        if finalDuration > 0 {
            summaryDuration = finalDuration
            showSummary = true
        }
    }

    // MARK: - Ticker

    private func startTicker() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                updateDisplay()
            }
    }

    private func stopTicker() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func updateDisplay() {
        var total = accumulatedSeconds
        if let start = startTime {
            total += Date().timeIntervalSince(start)
        }
        displaySeconds = total
    }

    // MARK: - Persistence

    private func persistState() {
        let defaults = UserDefaults.standard
        defaults.set(timerState.rawValue, forKey: DefaultsKey.state)
        defaults.set(accumulatedSeconds, forKey: DefaultsKey.accumulatedSeconds)
        if let start = startTime {
            defaults.set(start.timeIntervalSince1970, forKey: DefaultsKey.startTime)
        } else {
            defaults.removeObject(forKey: DefaultsKey.startTime)
        }
    }

    private func clearPersistedState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: DefaultsKey.state)
        defaults.removeObject(forKey: DefaultsKey.accumulatedSeconds)
        defaults.removeObject(forKey: DefaultsKey.startTime)
    }

    private func restoreState() {
        let defaults = UserDefaults.standard
        let stateString = defaults.string(forKey: DefaultsKey.state) ?? "idle"
        let restored = TimerState(rawValue: stateString) ?? .idle
        let accumulated = defaults.double(forKey: DefaultsKey.accumulatedSeconds)

        timerState = restored
        accumulatedSeconds = accumulated

        if restored == .running {
            let startInterval = defaults.double(forKey: DefaultsKey.startTime)
            if startInterval > 0 {
                startTime = Date(timeIntervalSince1970: startInterval)
            }
            updateDisplay()
            startTicker()
        } else if restored == .paused {
            startTime = nil
            displaySeconds = accumulated
            stopTicker()
        } else {
            startTime = nil
            displaySeconds = 0
            stopTicker()
        }
    }

    // MARK: - Data Loading

    private func loadRecentSessions() {
        if let cached = DreamingManager.shared.cachedExternalTimes {
            recentSessions = filterAndSortSessions(cached)
        } else {
            DreamingManager.shared.fetchExternalTimes { entries in
                DispatchQueue.main.async {
                    if let entries = entries {
                        recentSessions = filterAndSortSessions(entries)
                    }
                }
            }
        }
    }

    private func filterAndSortSessions(_ entries: [DreamingManager.ExternalTimeEntry]) -> [DreamingManager.ExternalTimeEntry] {
        entries
            .filter { $0.type == "talking" }
            .sorted { $0.date > $1.date }
            .prefix(10)
            .map { $0 }
    }

    // MARK: - Formatting

    private func formatTime(_ totalSeconds: Double) -> String {
        let total = Int(totalSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private func formatDurationShort(_ totalSeconds: Double) -> String {
        let total = Int(totalSeconds)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%dm %ds", minutes, seconds)
    }
}
