import Combine
import SwiftUI

struct TalkTimerView: View {
    enum TimerState: String {
        case idle
        case running
        case paused
    }

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

    private enum DefaultsKey {
        static let startTime = "TalkTimerStartTime"
        static let accumulatedSeconds = "TalkTimerAccumulatedSeconds"
        static let state = "TalkTimerState"
        static let primaryType = "TalkTimerPrimaryType"
        static let subType = "TalkTimerSubType"
        static let inputPercentage = "TalkTimerInputPercentage"
    }

    @EnvironmentObject var theme: Theme

    @State private var timerState: TimerState = .idle
    @State private var accumulatedSeconds: Double = 0
    @State private var startTime: Date?
    @State private var displaySeconds: Double = 0
    @State private var showSummary = false
    @State private var summaryDuration: Double?
    @State private var summaryKind: ManualEntryKind? = nil
    @State private var timerCancellable: AnyCancellable?

    @State private var primaryType: PrimaryType = .talking
    @State private var subType: TalkingSubType = .talking
    @State private var inputPercentage: Int = 100

    @Environment(\.dismiss) private var dismiss

    var onLogged: (() -> Void)? = nil

    var body: some View {
        NavigationView {
            ZStack {
                theme.primaryUi01
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    typePickerSection
                    Spacer()
                    timerDisplay
                    adjustButtons
                    controls
                    Spacer()
                    percentageStepper
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
        .onChange(of: primaryType) { _ in persistState() }
        .onChange(of: subType) { _ in persistState() }
        .onChange(of: inputPercentage) { _ in persistState() }
        .sheet(isPresented: $showSummary) {
            TalkSessionSummaryView(
                durationSeconds: summaryDuration,
                initialKind: summaryKind
            ) {
                onLogged?()
                dismiss()
            }
            .environmentObject(theme)
        }
    }

    // MARK: - Type Pickers

    private var typePickerSection: some View {
        VStack(spacing: 8) {
            Picker(L10n.entryType, selection: $primaryType) {
                ForEach(PrimaryType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)

            if primaryType == .talking {
                Picker(L10n.talkingSubType, selection: $subType) {
                    Text(L10n.talkingSubTypeTalking).tag(TalkingSubType.talking)
                    Text(L10n.talkTypeCrosstalk).tag(TalkingSubType.crosstalk)
                    Text(L10n.talkingSubTypeReverseCrosstalk).tag(TalkingSubType.reverseCrosstalk)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - Timer Display

    private var timerDisplay: some View {
        Text(formatTime(displaySeconds))
            .font(.system(size: 72, weight: .light, design: .monospaced))
            .monospacedDigit()
            .foregroundColor(theme.primaryText01)
    }

    // MARK: - +5 / -5 Buttons

    private var adjustButtons: some View {
        HStack(spacing: 24) {
            adjustButton(label: "-5", minutes: -5)
            adjustButton(label: "+5", minutes: 5)
        }
    }

    private func adjustButton(label: String, minutes: Int) -> some View {
        Button(action: { adjust(byMinutes: minutes) }) {
            Text(label)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(theme.primaryUi01)
                .frame(width: 64, height: 40)
                .background(theme.primaryInteractive01)
                .clipShape(Capsule())
        }
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

    // MARK: - Percentage Stepper

    private var percentageStepper: some View {
        Stepper(value: $inputPercentage, in: 0...100, step: 10) {
            HStack {
                Text(L10n.inputQuality)
                    .foregroundColor(theme.primaryText02)
                Spacer()
                Text("\(inputPercentage)%")
                    .font(.body.weight(.semibold))
                    .foregroundColor(theme.primaryText01)
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
        var rawDuration = accumulatedSeconds
        if let start = startTime {
            rawDuration += Date().timeIntervalSince(start)
        }
        let scaledDuration = rawDuration * Double(inputPercentage) / 100.0

        timerState = .idle
        startTime = nil
        accumulatedSeconds = 0
        displaySeconds = 0
        clearPersistedState()
        stopTicker()

        if scaledDuration > 0 {
            summaryDuration = scaledDuration
            summaryKind = currentKind
            showSummary = true
        }
    }

    private var currentKind: ManualEntryKind {
        switch primaryType {
        case .watching: return .watching(source: "", title: "")
        case .talking:  return .talking(subType: subType, userDescription: nil)
        }
    }

    private func adjust(byMinutes minutes: Int) {
        let delta = Double(minutes) * 60
        // Flush active slice into accumulated before applying delta, otherwise
        // the next tick (now - startTime) would overwrite the adjustment.
        if let start = startTime {
            accumulatedSeconds += Date().timeIntervalSince(start)
            startTime = Date()
        }
        accumulatedSeconds = max(0, accumulatedSeconds + delta)
        displaySeconds = accumulatedSeconds
        persistState()
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
        defaults.set(primaryType.rawValue, forKey: DefaultsKey.primaryType)
        defaults.set(subType.rawValue, forKey: DefaultsKey.subType)
        defaults.set(inputPercentage, forKey: DefaultsKey.inputPercentage)
    }

    private func clearPersistedState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: DefaultsKey.state)
        defaults.removeObject(forKey: DefaultsKey.accumulatedSeconds)
        defaults.removeObject(forKey: DefaultsKey.startTime)
        // Type pickers and percentage are intentionally NOT cleared on stop —
        // they survive across sessions so the user doesn't reset them every time.
    }

    private func restoreState() {
        let defaults = UserDefaults.standard
        let stateString = defaults.string(forKey: DefaultsKey.state) ?? "idle"
        let restored = TimerState(rawValue: stateString) ?? .idle
        let accumulated = defaults.double(forKey: DefaultsKey.accumulatedSeconds)

        timerState = restored
        accumulatedSeconds = accumulated

        if let primaryRaw = defaults.string(forKey: DefaultsKey.primaryType),
           let restoredPrimary = PrimaryType(rawValue: primaryRaw) {
            primaryType = restoredPrimary
        }
        if let subRaw = defaults.string(forKey: DefaultsKey.subType),
           let restoredSub = TalkingSubType(rawValue: subRaw) {
            subType = restoredSub
        }
        let persistedPercentage = defaults.object(forKey: DefaultsKey.inputPercentage) as? Int
        inputPercentage = persistedPercentage ?? 100

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
