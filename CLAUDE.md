@AGENTS.md

## Dreaming Spanish Integration

This fork adds integration with [Dreaming Spanish](https://www.dreamingspanish.com), a language learning platform that tracks hours of Spanish listening input. When a user configures a Dreaming Spanish bearer token, the app logs episode completions to the Dreaming Spanish API so listening time is automatically tracked.

### How it works

1. **Token setup:** The user enters their Dreaming Spanish bearer token in Settings > Dreaming (`DreamingSettingsViewController`). The token is stored in the Keychain via `DreamingManager`.

2. **Logging on completion:** When episodes are marked as played, `DreamingManager.shared.logEpisodeCompletions(episodes:)` is called. This is the single entry point for all Dreaming logging. It:
   - Early-returns if no token is configured
   - Resolves podcast titles internally (callers don't need to)
   - For a single episode: sends one API call with that episode's duration
   - For multiple episodes (bulk "Mark All Played"): groups by podcast, sums durations, and sends one API call per podcast with a combined description (e.g., "Podcast Name - Eps 1-5, 8, 12")

3. **Call sites** — logging is triggered from three places:
   - `EpisodeManager.markAsPlayed()` — single episode marked as played (includes "Skip Last" completion path)
   - `EpisodeManager.bulkMarkAsPlayed()` — bulk "Mark All Played"
   - `PlaybackManager.playerDidFinishPlayingEpisode()` — natural end-of-episode during playback (this path does NOT go through `EpisodeManager.markAsPlayed`)

4. **Status tracking:** Each logged episode gets a status (pending/success/failure) stored in UserDefaults. A `dreamingLogStatusChanged` notification updates the UI.

5. **UI indicator:** `EpisodeCell` shows a small icon next to episodes that have been logged — checkmark (success), clock (pending), or exclamation (failure).

### Key files

| File | Purpose |
|------|---------|
| `podcasts/Dreaming/DreamingManager.swift` | Singleton managing token storage, API calls, and log status |
| `podcasts/Dreaming/DreamingSettingsViewController.swift` | Settings screen for entering/removing the bearer token |
| `podcasts/EpisodeManager.swift` | Calls `logEpisodeCompletions` in `markAsPlayed` and `bulkMarkAsPlayed` |
| `podcasts/PlaybackManager.swift` | Calls `logEpisodeCompletions` in `playerDidFinishPlayingEpisode` |
| `podcasts/EpisodeCell.swift` | Displays dreaming log status indicator on episode cells |
| `podcasts/Constants.swift` | Defines `dreamingLogStatusChanged` notification name |
| `podcasts/SettingsViewController.swift` | Adds "Dreaming" row in settings navigation |

### API

The Dreaming Spanish external time API endpoint is:
```
POST https://app.dreaming.com/.netlify/functions/externalTime?language=es
Authorization: Bearer <token>
```
Body fields: `id`, `timeSeconds`, `description`, `type` ("listening"), `date` (yyyy-MM-dd), `idempotencyKey`, `externalVideoUrl`
