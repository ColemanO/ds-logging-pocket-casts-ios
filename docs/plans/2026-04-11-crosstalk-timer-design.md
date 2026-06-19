# Crosstalk Timer — v1 Design

## Overview

A new top-level "Talk" tab that provides a timer for tracking Dreaming Spanish crosstalk and output sessions. Sessions are logged to the same `externalTime` API endpoint used for podcast logging, with `type: "talking"`.

## Tab Bar Changes

- Remove the "Up Next" tab from the main tab bar
- Add a new "Talk" tab in its place
- Tab order becomes: Podcasts, Discover, **Talk**, Dreaming, Profile
- Tab enum gains `.talk` case, loses `.upNext`

## Main Screen (SwiftUI)

The Talk tab is a SwiftUI view hosted in a UIHostingController (wrapped in a UINavigationController for tab bar integration).

### Layout

- **Timer display** — large centered elapsed time (HH:MM:SS format)
- **Controls:**
  - Idle state: **Start** button
  - Running state: **Stop** and **Pause** buttons
  - Paused state: **Stop** and **Resume** buttons
- **Manual log button** — opens the summary screen with empty fields for manual entry
- **Recent sessions list** — shows recently logged talking sessions below the timer, pulled from `cachedExternalTimes` filtered to `type == "talking"`

### Timer Behavior

- On start: save `startTime` and `accumulatedSeconds` to UserDefaults
- On pause: add elapsed interval to `accumulatedSeconds`, clear `startTime`
- On resume: save new `startTime`
- On stop: compute final duration, navigate to summary screen, clear persisted state
- On app foreground: if `startTime` exists, compute elapsed from saved start time (timer survives backgrounding and app termination)

## Summary/Edit Screen (SwiftUI)

Displayed when the timer is stopped or when the manual log button is tapped.

### Fields

| Field | Default | Editable |
|-------|---------|----------|
| Duration | From timer (or blank for manual) | Yes |
| Type | Crosstalk | Yes — picker: Crosstalk / Output |
| Description | "Crosstalk session" or "Output session" | Yes — text field |
| Date | Today | Yes — date picker |

### Actions

- **Log** — POST to `externalTime` endpoint with `type: "talking"`, then dismiss
- **Discard** — dismiss without logging

## API

Same endpoint and payload shape as podcast logging:

```
POST https://app.dreaming.com/.netlify/functions/externalTime?language=es
Authorization: Bearer <token>
```

Body:
```json
{
  "id": "<uuid>-<timestamp>",
  "timeSeconds": <duration>,
  "description": "Crosstalk session",
  "type": "talking",
  "date": "2026-04-11",
  "idempotencyKey": "<uuid>",
  "externalVideoUrl": ""
}
```

## Key Files (New)

| File | Purpose |
|------|---------|
| `podcasts/Dreaming/TalkTimerView.swift` | Main SwiftUI view with timer and session list |
| `podcasts/Dreaming/TalkSessionSummaryView.swift` | Summary/edit screen for logging sessions |

## Key Files (Modified)

| File | Change |
|------|--------|
| `podcasts/MainTabBarController.swift` | Replace `.upNext` with `.talk` in Tab enum and tab setup |
| `podcasts/Dreaming/DreamingManager.swift` | Add `logTalkSession()` method for posting talking entries |
