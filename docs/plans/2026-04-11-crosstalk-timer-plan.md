# Crosstalk Timer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a "Talk" tab to the main tab bar with a crosstalk/output timer that logs sessions to the Dreaming Spanish API.

**Architecture:** SwiftUI views hosted in UIHostingController, integrated into the existing UIKit tab bar. Timer state persisted in UserDefaults for background survival. API logging reuses the existing `externalTime` endpoint pattern in `DreamingManager`.

**Tech Stack:** SwiftUI, UIKit (tab bar integration), URLSession, UserDefaults

---

### Task 1: Add `logTalkSession()` to DreamingManager

**Files:**
- Modify: `podcasts/Dreaming/DreamingManager.swift`

**Step 1: Add the `logTalkSession` method**

Add this method to `DreamingManager` after the existing `logEpisodeCompletion` method (after line 612):

```swift
// MARK: - Talk Session Logging

func logTalkSession(timeSeconds: Double, description: String, date: Date, completion: @escaping (Bool) -> Void) {
    guard let token = getToken() else {
        FileLog.shared.addMessage("Dreaming: No token configured, skipping talk session log")
        completion(false)
        return
    }

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    let dateString = dateFormatter.string(from: date)

    let timestamp = Int(Date().timeIntervalSince1970)
    let idempotencyKey = UUID().uuidString

    let body: [String: Any] = [
        "id": "talk-\(timestamp)",
        "timeSeconds": timeSeconds,
        "description": description,
        "type": "talking",
        "date": dateString,
        "idempotencyKey": idempotencyKey,
        "externalVideoUrl": ""
    ]

    guard let url = URL(string: "https://app.dreaming.com/.netlify/functions/externalTime?language=es"),
          let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
        FileLog.shared.addMessage("Dreaming: Failed to create talk session request")
        completion(false)
        return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = jsonData
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

    URLSession.shared.dataTask(with: request) { _, response, error in
        if let error = error {
            FileLog.shared.addMessage("Dreaming: Failed to log talk session - \(error.localizedDescription)")
            DispatchQueue.main.async { completion(false) }
            return
        }

        if let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) {
            FileLog.shared.addMessage("Dreaming: Successfully logged talk session")
            DispatchQueue.main.async { completion(true) }
        } else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            FileLog.shared.addMessage("Dreaming: Failed to log talk session, status code: \(statusCode)")
            DispatchQueue.main.async { completion(false) }
        }
    }.resume()
}
```

**Step 2: Verify build**

Run: `make build`
Expected: Build succeeds (or only provisioning profile errors, no Swift compilation errors)

**Step 3: Commit**

```bash
git add podcasts/Dreaming/DreamingManager.swift
git commit -m "feat: add logTalkSession() to DreamingManager"
```

---

### Task 2: Create TalkSessionSummaryView (summary/edit screen)

**Files:**
- Create: `podcasts/Dreaming/TalkSessionSummaryView.swift`

**Step 1: Create the summary view**

```swift
import SwiftUI

struct TalkSessionSummaryView: View {
    enum TalkType: String, CaseIterable {
        case crosstalk = "Crosstalk"
        case output = "Output"
    }

    @Environment(\.dismiss) private var dismiss

    @State var durationMinutes: String
    @State var durationSeconds: String
    @State var talkType: TalkType = .crosstalk
    @State var descriptionText: String = "Crosstalk session"
    @State var date: Date = Date()
    @State private var isLogging = false
    @State private var showError = false

    let initialDurationSeconds: Double?
    let onLogged: (() -> Void)?

    init(durationSeconds: Double? = nil, onLogged: (() -> Void)? = nil) {
        self.initialDurationSeconds = durationSeconds
        self.onLogged = onLogged
        if let dur = durationSeconds {
            let totalSec = Int(dur)
            _durationMinutes = State(initialValue: "\(totalSec / 60)")
            _durationSeconds = State(initialValue: "\(totalSec % 60)")
        } else {
            _durationMinutes = State(initialValue: "")
            _durationSeconds = State(initialValue: "0")
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Duration") {
                    HStack {
                        TextField("Min", text: $durationMinutes)
                            .keyboardType(.numberPad)
                            .frame(width: 60)
                        Text("m")
                        TextField("Sec", text: $durationSeconds)
                            .keyboardType(.numberPad)
                            .frame(width: 60)
                        Text("s")
                    }
                }

                Section("Type") {
                    Picker("Type", selection: $talkType) {
                        ForEach(TalkType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: talkType) { newValue in
                        descriptionText = "\(newValue.rawValue) session"
                    }
                }

                Section("Description") {
                    TextField("Description", text: $descriptionText)
                }

                Section("Date") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
            }
            .navigationTitle("Log Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        logSession()
                    }
                    .disabled(isLogging || totalSeconds <= 0)
                }
            }
            .alert("Failed to log session", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private var totalSeconds: Double {
        let mins = Double(durationMinutes) ?? 0
        let secs = Double(durationSeconds) ?? 0
        return (mins * 60) + secs
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
```

**Step 2: Add to Xcode project manually, then verify build**

Run: `make build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add podcasts/Dreaming/TalkSessionSummaryView.swift
git commit -m "feat: add TalkSessionSummaryView for logging talk sessions"
```

---

### Task 3: Create TalkTimerView (main timer screen)

**Files:**
- Create: `podcasts/Dreaming/TalkTimerView.swift`

**Step 1: Create the timer view**

```swift
import SwiftUI

struct TalkTimerView: View {
    enum TimerState {
        case idle, running, paused
    }

    private static let startTimeKey = "TalkTimerStartTime"
    private static let accumulatedKey = "TalkTimerAccumulatedSeconds"
    private static let stateKey = "TalkTimerState"

    @State private var timerState: TimerState = .idle
    @State private var accumulatedSeconds: Double = 0
    @State private var displaySeconds: Double = 0
    @State private var showingSummary = false
    @State private var showingManualLog = false
    @State private var stoppedDuration: Double = 0
    @State private var recentSessions: [DreamingManager.ExternalTimeEntry] = []

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 40)

                // Timer display
                Text(formatTime(displaySeconds))
                    .font(.system(size: 64, weight: .light, design: .monospaced))
                    .monospacedDigit()

                // Controls
                HStack(spacing: 24) {
                    switch timerState {
                    case .idle:
                        timerButton("Start", color: .green) { startTimer() }
                    case .running:
                        timerButton("Pause", color: .orange) { pauseTimer() }
                        timerButton("Stop", color: .red) { stopTimer() }
                    case .paused:
                        timerButton("Resume", color: .green) { resumeTimer() }
                        timerButton("Stop", color: .red) { stopTimer() }
                    }
                }

                Button("Log Manually") {
                    showingManualLog = true
                }
                .font(.system(size: 15))
                .foregroundColor(.blue)

                // Recent sessions
                if !recentSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Sessions")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(recentSessions, id: \.id) { session in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.description)
                                        .font(.system(size: 14))
                                    Text(session.date)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(formatTime(session.timeSeconds))
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Spacer()
            }
            .padding()
        }
        .onAppear {
            restoreTimerState()
            loadRecentSessions()
        }
        .onReceive(timer) { _ in
            updateDisplay()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            restoreTimerState()
        }
        .sheet(isPresented: $showingSummary) {
            TalkSessionSummaryView(durationSeconds: stoppedDuration) {
                loadRecentSessions()
            }
        }
        .sheet(isPresented: $showingManualLog) {
            TalkSessionSummaryView {
                loadRecentSessions()
            }
        }
    }

    // MARK: - Timer Controls

    private func startTimer() {
        accumulatedSeconds = 0
        timerState = .running
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.startTimeKey)
        UserDefaults.standard.set(0.0, forKey: Self.accumulatedKey)
        UserDefaults.standard.set("running", forKey: Self.stateKey)
    }

    private func pauseTimer() {
        let elapsed = currentElapsed()
        accumulatedSeconds += elapsed
        timerState = .paused
        UserDefaults.standard.removeObject(forKey: Self.startTimeKey)
        UserDefaults.standard.set(accumulatedSeconds, forKey: Self.accumulatedKey)
        UserDefaults.standard.set("paused", forKey: Self.stateKey)
    }

    private func resumeTimer() {
        timerState = .running
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.startTimeKey)
        UserDefaults.standard.set(accumulatedSeconds, forKey: Self.accumulatedKey)
        UserDefaults.standard.set("running", forKey: Self.stateKey)
    }

    private func stopTimer() {
        let total = accumulatedSeconds + currentElapsed()
        stoppedDuration = total
        timerState = .idle
        accumulatedSeconds = 0
        displaySeconds = 0
        clearPersistedState()
        showingSummary = true
    }

    // MARK: - Persistence

    private func restoreTimerState() {
        let stateStr = UserDefaults.standard.string(forKey: Self.stateKey) ?? "idle"
        let accumulated = UserDefaults.standard.double(forKey: Self.accumulatedKey)
        accumulatedSeconds = accumulated

        switch stateStr {
        case "running":
            timerState = .running
            updateDisplay()
        case "paused":
            timerState = .paused
            displaySeconds = accumulated
        default:
            timerState = .idle
            displaySeconds = 0
        }
    }

    private func clearPersistedState() {
        UserDefaults.standard.removeObject(forKey: Self.startTimeKey)
        UserDefaults.standard.removeObject(forKey: Self.accumulatedKey)
        UserDefaults.standard.removeObject(forKey: Self.stateKey)
    }

    private func currentElapsed() -> Double {
        let startTime = UserDefaults.standard.double(forKey: Self.startTimeKey)
        guard startTime > 0 else { return 0 }
        return Date().timeIntervalSince1970 - startTime
    }

    private func updateDisplay() {
        guard timerState == .running else { return }
        displaySeconds = accumulatedSeconds + currentElapsed()
    }

    // MARK: - Recent Sessions

    private func loadRecentSessions() {
        guard let cached = DreamingManager.shared.cachedExternalTimes else {
            DreamingManager.shared.fetchExternalTimes { entries in
                DispatchQueue.main.async {
                    recentSessions = (entries ?? [])
                        .filter { $0.type == "talking" }
                        .sorted { $0.date > $1.date }
                        .prefix(10)
                        .map { $0 }
                }
            }
            return
        }
        recentSessions = cached
            .filter { $0.type == "talking" }
            .sorted { $0.date > $1.date }
            .prefix(10)
            .map { $0 }
    }

    // MARK: - Helpers

    private func formatTime(_ totalSeconds: Double) -> String {
        let h = Int(totalSeconds) / 3600
        let m = (Int(totalSeconds) % 3600) / 60
        let s = Int(totalSeconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    private func timerButton(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 100, height: 100)
                .background(color)
                .clipShape(Circle())
        }
    }
}
```

**Step 2: Add to Xcode project manually, then verify build**

Run: `make build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add podcasts/Dreaming/TalkTimerView.swift
git commit -m "feat: add TalkTimerView with start/stop/pause and background persistence"
```

---

### Task 4: Replace "Up Next" tab with "Talk" tab

**Files:**
- Modify: `podcasts/MainTabBarController.swift` (lines 11, 56, 70-71, 76)

**Step 1: Update the Tab enum**

Change line 11 from:
```swift
enum Tab: Int { case podcasts, filter, discover, profile, upNext, dreaming }
```
to:
```swift
enum Tab: Int { case podcasts, filter, discover, profile, talk, dreaming }
```

**Step 2: Update pcTabs array**

Change line 56 from:
```swift
pcTabs = [.podcasts, .discover, .upNext, .dreaming, .profile]
```
to:
```swift
pcTabs = [.podcasts, .discover, .talk, .dreaming, .profile]
```

**Step 3: Replace UpNext view controller with Talk**

Replace lines 70-71:
```swift
let upNextViewController = UpNextViewController(source: .tabBar, showingInTab: true)
upNextViewController.tabBarItem = UITabBarItem(title: L10n.upNext, image: UIImage(named: "upnext_tab"), tag: pcTabs.firstIndex(of: .upNext)!)
```
with:
```swift
let talkViewController = UIHostingController(rootView: TalkTimerView())
talkViewController.tabBarItem = UITabBarItem(title: "Talk", image: UIImage(systemName: "mic.fill"), tag: pcTabs.firstIndex(of: .talk)!)
```

**Step 4: Update vcsInTab array**

Change line 76 from:
```swift
vcsInTab = [podcastsController, discoverViewController, upNextViewController, dreamingViewController, profileViewController]
```
to:
```swift
vcsInTab = [podcastsController, discoverViewController, talkViewController, dreamingViewController, profileViewController]
```

**Step 5: Search for any other `.upNext` references and update**

Search for `.upNext` in MainTabBarController.swift and update any remaining references to `.talk`.

**Step 6: Verify build**

Run: `make build`
Expected: Build succeeds

**Step 7: Commit**

```bash
git add podcasts/MainTabBarController.swift
git commit -m "feat: replace Up Next tab with Talk tab in main tab bar"
```

---

### Task 5: Format and final build check

**Step 1: Run formatter**

Run: `make format`

**Step 2: Verify build**

Run: `make build`
Expected: Build succeeds

**Step 3: Commit any formatting changes**

```bash
git add -A
git commit -m "style: format crosstalk timer files"
```
