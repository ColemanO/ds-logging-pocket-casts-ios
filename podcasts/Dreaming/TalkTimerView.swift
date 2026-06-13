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

    @EnvironmentObject var theme: Theme

    @State private var timerState: TimerState = .idle
    @State private var accumulatedSeconds: Double = 0
    @State private var startTime: Date?
    @State private var displaySeconds: Double = 0
    @State private var showSummary = false
    @State private var summaryDuration: Double?
    @State private var timerCancellable: AnyCancellable?

    @Environment(\.dismiss) private var dismiss

    var onLogged: (() -> Void)? = nil

    var body: some View {
        NavigationView {
            ZStack {
                theme.primaryUi01
                    .ignoresSafeArea()

                VStack(spacing: 40) {
                    Spacer()
                    timerDisplay
                    controls
                    Spacer()
                }
                .padding()
            }
            .navigationTitle(L10n.talk)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.close) {
                        dismiss()
                    }
                    .foregroundColor(theme.primaryInteractive01)
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear(perform: restoreState)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            restoreState()
        }
        .sheet(isPresented: $showSummary) {
            TalkSessionSummaryView(durationSeconds: summaryDuration) {
                onLogged?()
                dismiss()
            }
            .environmentObject(theme)
        }
    }

    // MARK: - Timer Display

    private var timerDisplay: some View {
        Text(formatTime(displaySeconds))
            .font(.system(size: 72, weight: .light, design: .monospaced))
            .monospacedDigit()
            .foregroundColor(theme.primaryText01)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 32) {
            switch timerState {
            case .idle:
                Button(action: start) {
                    timerButton(label: L10n.talkStart, color: theme.support02)
                }
            case .running:
                Button(action: pause) {
                    timerButton(label: L10n.talkPause, color: .orange)
                }
                Button(action: stop) {
                    timerButton(label: L10n.talkStop, color: theme.support05)
                }
            case .paused:
                Button(action: resume) {
                    timerButton(label: L10n.talkResume, color: theme.support02)
                }
                Button(action: stop) {
                    timerButton(label: L10n.talkStop, color: theme.support05)
                }
            }
        }
    }

    private func timerButton(label: String, color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 80, height: 80)
            .overlay(
                Text(label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            )
            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
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
}
