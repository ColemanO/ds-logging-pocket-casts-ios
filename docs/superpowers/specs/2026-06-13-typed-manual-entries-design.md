# Typed manual entries — design

Date: 2026-06-13
Status: Approved

## Goal

Replace the talking-only manual entry flow with a structured, type-aware system. Users can log Watching (YouTube / TV / any video source) and Talking (with sub-types: Talking, Crosstalk, Reverse Crosstalk) entries from both the manual form and the timer screen. Add +5/-5 minute adjusters and an input-quality percentage stepper to the timer. Introduce a `ManualEntryKind` enum that encodes to / decodes from the Dreaming Spanish `(type, description)` pair so future chart code has a structured handle on manual entries.

## Scope

### In scope

- New `ManualEntryKind` enum + supporting `TalkingSubType` enum in a new file `podcasts/Dreaming/ManualEntryKind.swift`. Encodes to `(apiType, description)`; decodes back.
- Replace `DreamingManager.logTalkSession(...)` with a generalized `logExternalEntry(type:description:timeSeconds:date:completion:)`. Same body shape and behavior; just takes `type` as a parameter and uses a `"<type>-<timestamp>"` id prefix.
- Rebuild `TalkSessionSummaryView` around the new enum: primary type picker (Watching / Talking), conditional field block (Source/Title for Watching; sub-type picker + optional description for Talking), unchanged Duration / Date / buttons sections.
- Extend `TalkTimerView`:
  - Primary + sub-type pickers at the top.
  - `[-5]` `[+5]` minute buttons (always visible, clamp at 0, adjust raw accumulated time).
  - "Input quality" stepper (0–100%, 10% increments, default 100%) that scales the duration at stop.
  - Pass the timer's selected `ManualEntryKind` (without source/title/userDescription text fields) into the summary as `initialKind`.
- Persist primary type, sub-type, and percentage to UserDefaults alongside existing timer state.
- Add new L10n keys (sub-type labels, field labels, percentage label). Remove the now-unused `talk_crosstalk_session` / `talk_output_session` keys.
- Activity-list rendering falls back to the raw `ExternalTimeEntry.description` for any entry that doesn't decode to a `ManualEntryKind` (e.g. legacy `"Crosstalk Session"`, podcast auto-logs).

### Out of scope

- Charts that consume the decoded data (separate future PR).
- `externalVideoUrl` submission for YouTube (potentially separate future PR — lets DS auto-classify).
- Recently-used Source autocomplete.
- One-shot migration of legacy `"Crosstalk Session"` / `"Output Session"` entries (left as-is; see Legacy handling).
- Editing existing entries.
- Removing the `.talk` enum case from `pcTabs` or renaming the local `talkViewController` variable in `MainTabBarController` — those are internal names that don't surface to the user and would ripple through analytics code unnecessarily.

## Data model

New file `podcasts/Dreaming/ManualEntryKind.swift`:

```swift
import Foundation

/// Sub-type of a "talking" entry — the part that prefixes the description string.
enum TalkingSubType: String, CaseIterable, Identifiable {
    case talking = "Talking"
    case crosstalk = "Crosstalk"
    case reverseCrosstalk = "Reverse Crosstalk"

    var id: String { rawValue }
    var displayName: String { rawValue }
}

/// Discriminated representation of a manual entry the user creates.
/// Encodes to `(apiType, description)` for submission; decodes back from
/// the same pair when reading entries from Dreaming Spanish.
enum ManualEntryKind: Equatable {
    case watching(source: String, title: String)
    case talking(subType: TalkingSubType, userDescription: String?)

    /// Maps to the Dreaming Spanish `type` field.
    var apiType: String {
        switch self {
        case .watching: return "watching"
        case .talking: return "talking"
        }
    }

    /// Builds the description string we send to Dreaming Spanish.
    /// Watching: "<source> | <title>"; if only one side has content, no pipe.
    /// Talking: "<SubType>" alone or "<SubType> | <user desc>" if present.
    var encodedDescription: String {
        switch self {
        case .watching(let source, let title):
            let s = source.trimmingCharacters(in: .whitespaces)
            let t = title.trimmingCharacters(in: .whitespaces)
            switch (s.isEmpty, t.isEmpty) {
            case (false, false): return "\(s) | \(t)"
            case (false, true):  return s
            case (true, false):  return t
            case (true, true):   return ""
            }
        case .talking(let subType, let userDescription):
            let trimmed = userDescription?.trimmingCharacters(in: .whitespaces) ?? ""
            return trimmed.isEmpty ? subType.rawValue : "\(subType.rawValue) | \(trimmed)"
        }
    }

    /// Parses a Dreaming Spanish entry back into its manual-entry shape.
    /// Returns nil for entries that don't match the manual format
    /// (podcast auto-logs, the `initial` lifetime entry, or legacy
    /// "Crosstalk Session" / "Output Session" strings).
    static func decode(apiType: String, description: String) -> ManualEntryKind? {
        let parts = description.components(separatedBy: " | ")
        let group = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
        let specific = parts.count > 1
            ? parts.dropFirst().joined(separator: " | ").trimmingCharacters(in: .whitespaces)
            : ""

        switch apiType {
        case "watching":
            // Defensive: an entry with no source AND no title is meaningless.
            // Treat as undecodable so the UI falls back to the raw string.
            if group.isEmpty && specific.isEmpty { return nil }
            return .watching(source: group, title: specific)
        case "talking":
            guard let subType = TalkingSubType(rawValue: group) else {
                return nil // legacy talking entry; render the raw description as-is
            }
            return .talking(subType: subType, userDescription: specific.isEmpty ? nil : specific)
        default:
            return nil // listening (podcasts), initial, etc. — not manual entries
        }
    }
}
```

**Notes on the shape:**

- `Equatable` so SwiftUI `@State` and `.onChange` work cleanly.
- `decode` is non-throwing and returns `nil` for unmatched cases — the caller decides how to display unmatched entries.
- `encodedDescription` trims whitespace before checking emptiness; a trailing space in a text field won't produce `"PewDiePie | "`.
- `TalkingSubType.rawValue` doubles as the description prefix — keeps encode/decode symmetric and removes a separate `prefix:` field.
- Watching decode tolerates: missing pipe, multiple pipes (extras fold into title), single-field entries. Only fully-empty descriptions return nil.

## Manager API change

Replace `DreamingManager.logTalkSession(timeSeconds:description:date:completion:)` with:

```swift
func logExternalEntry(
    type: String,
    description: String,
    timeSeconds: Double,
    date: Date,
    completion: @escaping (Bool) -> Void
)
```

Differences from the current method:

- Takes `type` as a parameter (no more hardcoded `"talking"`).
- The `id` prefix changes from `"talk-"` to `"\(type)-"`: `talking-1781371125`, `watching-1781371125`. Keeps IDs scannable when reading raw DS data.
- Everything else stays identical — same `date` / `today` / `idempotencyKey` / body shape / status code handling / log lines.

Call sites that change:

- `TalkSessionSummaryView.logSession()` — calls `logExternalEntry(type: kind.apiType, description: kind.encodedDescription, ...)`.

The forms own the encoding (build a `ManualEntryKind`, ask it for `apiType` + `encodedDescription`, pass both to the manager). The manager stays a thin HTTP wrapper — no business logic about what types are valid.

## Manual screen — `TalkSessionSummaryView`

### State (replaces the old `TalkType`, `talkType`, `descriptionText`)

```swift
@State private var primaryType: PrimaryType = .talking
@State private var subType: TalkingSubType = .talking
@State private var watchingSource: String = ""
@State private var watchingTitle: String = ""
@State private var talkingUserDescription: String = ""
```

where `PrimaryType` is a local enum:

```swift
private enum PrimaryType: String, CaseIterable, Identifiable {
    case watching = "Watching"
    case talking = "Talking"
    var id: String { rawValue }
}
```

### Sections (top to bottom)

1. **Duration** (unchanged) — min / sec text fields → computed `totalSeconds`.
2. **Type** (new) — segmented `Picker` over `PrimaryType`. Default `.talking`.
3. **Conditional fields** (new) — one Section whose contents swap on `primaryType`:
   - **Watching:** `TextField(L10n.watchingSource, text: $watchingSource)` and `TextField(L10n.watchingTitle, text: $watchingTitle)`.
   - **Talking:** segmented `Picker` over `TalkingSubType` + `TextField(L10n.talkingDescription, text: $talkingUserDescription)`.
4. **Date** (unchanged) — existing `DatePicker`.
5. **Buttons** (unchanged) — Log + Discard.

### Computed kind & submission

```swift
private var kind: ManualEntryKind {
    switch primaryType {
    case .watching:
        return .watching(source: watchingSource, title: watchingTitle)
    case .talking:
        return .talking(subType: subType,
                        userDescription: talkingUserDescription.isEmpty ? nil : talkingUserDescription)
    }
}
```

### Log button disabled when

- `totalSeconds <= 0`, OR
- `isLogging`, OR
- `kind.encodedDescription.isEmpty` — covers the "Watching with both fields empty" case.

### Init signature

```swift
init(durationSeconds: Double? = nil, initialKind: ManualEntryKind? = nil, onLogged: (() -> Void)? = nil)
```

If `initialKind` is non-nil, populate the matching `@State`s. The timer passes a kind with only the picker selections filled (source/title/userDescription remain `""` — the user types those on the summary).

### Removed

- Local enum `TalkType { .crosstalk, .output }`.
- `@State descriptionText`.
- `.onChange(of: talkType)` that toggled `descriptionText` between the legacy strings.

## Timer screen — `TalkTimerView`

### New state (in addition to existing timer state)

```swift
@State private var primaryType: PrimaryType = .talking
@State private var subType: TalkingSubType = .talking
@State private var inputPercentage: Int = 100   // 0...100, stepped by 10
@State private var summaryKind: ManualEntryKind? = nil
```

(Source / Title / Talking user-description are *not* on the timer — they're entered on the summary after stop.)

### Layout

```
Nav bar:   [Close]                  Activity Timer
─────────────────────────────────────────────────
           [Watching | Talking]    ← primary type, segmented
           [sub-type segmented]    ← only when primary == .talking
─────────────────────────────────────────────────
                   00:42:15        ← big timer display
─────────────────────────────────────────────────
           [-5]            [+5]    ← minute adjustments
─────────────────────────────────────────────────
           [Start] or [Pause][Stop] or [Resume][Stop]
─────────────────────────────────────────────────
           Input quality
           [-]    100%    [+]      ← Stepper, 10% step, 0–100
─────────────────────────────────────────────────
```

When `primaryType == .watching`, the sub-type row is hidden (Watching has no sub-types in this design).

### +5 / -5 behavior

```swift
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
```

- Always visible (idle / running / paused).
- Clamps at 0 via `max(0, ...)`.
- Adjusts raw accumulated time (the percentage applies at stop, not here).

### Stop flow

```swift
private func stop() {
    var rawDuration = accumulatedSeconds
    if let start = startTime { rawDuration += Date().timeIntervalSince(start) }

    let scaledDuration = rawDuration * Double(inputPercentage) / 100.0

    timerState = .idle
    startTime = nil
    accumulatedSeconds = 0
    displaySeconds = 0
    clearPersistedState()
    stopTicker()

    if scaledDuration > 0 {
        summaryDuration = scaledDuration
        summaryKind = currentKind   // kind built from primaryType + subType
        showSummary = true
    }
}

private var currentKind: ManualEntryKind {
    switch primaryType {
    case .watching: return .watching(source: "", title: "")
    case .talking:  return .talking(subType: subType, userDescription: nil)
    }
}
```

The scaled value is what gets passed to the summary; the user doesn't see "raw vs effective" anywhere because by their own preference, *"after the entry is made we don't need to know how much it was scaled."*

### Sheet presentation

```swift
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
```

### Persistence (extends existing UserDefaults keys)

Add three new keys alongside `TalkTimerStartTime`, `TalkTimerAccumulatedSeconds`, `TalkTimerState`:

```swift
private enum DefaultsKey {
    // existing...
    static let primaryType = "TalkTimerPrimaryType"
    static let subType = "TalkTimerSubType"
    static let inputPercentage = "TalkTimerInputPercentage"
}
```

`persistState()` writes them; `restoreState()` reads them and falls back to defaults if absent.

## Legacy handling

### Existing `"Crosstalk Session"` / `"Output Session"` entries in DS

These don't decode to a `TalkingSubType` (prefix isn't an exact match). Behavior: `ManualEntryKind.decode(...)` returns `nil`. The Activity list still renders these rows — it iterates `ExternalTimeEntry` directly, not `ManualEntryKind`, and uses `entry.description` as the row label.

Net effect:

- The row shows the raw text (`"Crosstalk Session"`).
- The "Talking" chip filter still includes them (the chip filters by `entry.type == "talking"`, independent of decode success).
- When charts ship later, they'll absorb undecodable entries into an "Other" bucket; backfilling can be decided then.

### Unused L10n strings

`talk_crosstalk_session` and `talk_output_session` are no longer referenced anywhere after this PR's `TalkSessionSummaryView` rewrite. Implementation step: grep the codebase for references before deleting. If only the form references them, delete from `Localizable.strings` and let the L10n build phase regenerate `Strings+Generated.swift` without those accessors. If somehow another file uses them, leave them in place — flag for the user.

### New L10n strings

Added to `Localizable.strings` (the L10n build phase regenerates the accessors):

```
/* Primary type: Watching */
"primary_type_watching" = "Watching";

/* Primary type: Talking */
"primary_type_talking" = "Talking";

/* Talking sub-type: Talking (output speech with no partner) */
"talking_sub_type_talking" = "Talking";

/* Talking sub-type: Reverse Crosstalk */
"talking_sub_type_reverse_crosstalk" = "Reverse Crosstalk";

/* Watching field: Source (creator, channel, series) */
"watching_source" = "Source";

/* Watching field: Title (video / episode) */
"watching_title" = "Title";

/* Talking field: optional user description */
"talking_description" = "Description (optional)";

/* Input-quality percentage label on the timer */
"input_quality" = "Input quality";

/* Talking sub-type picker section header */
"talking_sub_type" = "Sub-type";
```

`talk_type_crosstalk` (existing) stays — the sub-type picker reuses it for `.crosstalk`. We don't need a new key for that.

## File-level change summary

- `podcasts/Dreaming/ManualEntryKind.swift` — **new file**.
- `podcasts/Dreaming/DreamingManager.swift` — replace `logTalkSession(...)` with `logExternalEntry(type:description:timeSeconds:date:completion:)`. Change id prefix to use `type`.
- `podcasts/Dreaming/TalkSessionSummaryView.swift` — replace form contents (new state, new sections, conditional fields, new `initialKind` init parameter). Delete the local `TalkType` enum and `descriptionText` state.
- `podcasts/Dreaming/TalkTimerView.swift` — add pickers, +5/-5 buttons, percentage stepper, new state, extend persistence, pass `summaryKind` to the summary sheet.
- `podcasts/en.lproj/Localizable.strings` — add the new keys above; remove `talk_crosstalk_session` and `talk_output_session` (after grepping).
- `podcasts/Strings+Generated.swift` — regenerated by the L10n build phase.
- `podcasts.xcodeproj/project.pbxproj` — register `ManualEntryKind.swift` (PBXBuildFile + PBXFileReference + group entry + Sources phase entry; follow the pattern used when adding `ManualEntriesView.swift` earlier).

## Verification

No new unit tests (no existing pattern for view-level tests in this codebase's Dreaming code). Manual verification on simulator covers the changes.

### Build check (each task)

```
xcodebuild -project podcasts.xcodeproj -scheme pocketcasts -configuration Debug \
  -destination 'platform=iOS Simulator,id=7AB43694-2429-4444-BDC2-939523447581' \
  CODE_SIGNING_ALLOWED=NO build
```

Ends with `** BUILD SUCCEEDED **`.

### Smoke test (single pass at end)

1. **Watching with both fields:** + → Manual → Watching → Source = "Test Channel", Title = "Test Video" → duration 1m → Log. Expect row `"Test Channel | Test Video"` today, 1m.
2. **Watching with one field:** Source = "Test Channel" only → Log enabled → submitted description = `"Test Channel"`.
3. **Watching both empty:** Log button disabled.
4. **Talking sub-type only:** + → Manual → Talking → Crosstalk → duration 1m → Log. Expect row `"Crosstalk"`.
5. **Talking with description:** Crosstalk + description "with mom" → row shows `"Crosstalk | with mom"`.
6. **Timer +5/-5 idle:** + → Timer → +5 four times → 20:00. -5 once → 15:00. -5 three more times → 0:00 (clamps).
7. **Timer +5 running:** Start timer, wait ~5s, +5 → timer ~5:05, continues counting.
8. **Timer percentage:** Reset. Stepper to 50%. +5 → 5:00 on display. Stop → summary opens prefilled at 2 min 30 sec.
9. **Timer type pre-fill:** Timer → pick Watching → Stop → summary opens with Watching primary type already selected, Source/Title empty.
10. **Override on summary:** From #9, switch to Talking on the summary → sub-type picker appears → submit. Entry is `type: talking`.
11. **Persistence:** Timer running with Watching + 60% selected → force-quit → reopen → state restored.
12. **Activity list legacy row:** If your account has an old `"Crosstalk Session"` entry, it still renders under the Talking chip with the raw description.
