## Overview

This repository is an iOS and watchOS Pocket Casts app workspace built around `podcasts.xcodeproj`.

Main areas:
- `podcasts/` contains the primary iOS app code.
- `PocketCastsTests/` contains the unit test target covered by `make test`.
- `Modules/` contains Swift packages such as `DataModel`, `DependencyInjection`, `Server`, and `Utils`.
- `BuildTools/` contains Swift Package plugins used by repo tooling, including SwiftLint-based linting and formatting.
- Extension and companion targets live in directories such as `WidgetExtension/`, `NotificationExtension/`, `Share Extension/`, `Pocket Casts Watch App/`, and `Pocket Casts App Clip/`.

## Formatting

Format all code using the repo formatter:

```bash
make format
```

This runs SwiftLint autocorrect through the `BuildTools` package plugin. Prefer this over ad hoc formatting.

## Building

Build the app with:

```bash
make build
```

This runs `xcodebuild` against `podcasts.xcodeproj` with the `pocketcasts` scheme in `Debug`.

## Testing

Run tests with:

```bash
make test
```

This runs `xcodebuild test` for the `pocketcasts` scheme and currently scopes to `PocketCastsTests`.

## Setup

Initial dependency setup:

```bash
make install_dependencies
```

This installs the Ruby/Bundler dependencies used by repo tooling such as `fastlane`.

For external contributors, run:

```bash
make external_contributor
```

That creates `podcasts/Credentials/LocalApiCredentials.swift` from the template so the app can build without internal secrets. The build scripts will prefer that local credentials file when present.

## Generated Code And Tooling

Useful project maintenance commands:

```bash
make lint
make generate_code
make update_proto API_PATH=/full/path/to/pocketcasts-api/api/modules/protobuf/src/main/proto
```

Notes:
- `make generate_code` runs the SwiftGen/resource generation plugin from `BuildTools`.
- `make update_proto` regenerates protobuf-backed server objects and depends on local `protobuf` and `swift-protobuf` tooling.
- If you touch generated resources, protobuf definitions, or lint-sensitive Swift code, run the relevant generation command and then `make format`.

## Project-Specific Notes

This fork includes Dreaming Spanish integration. Keep these behaviors intact when editing playback or completion flows:
- `DreamingManager.shared.logEpisodeCompletions(episodes:)` is the single entry point for episode completion logging.
- Logging is triggered from `EpisodeManager.markAsPlayed()`, `EpisodeManager.bulkMarkAsPlayed()`, and `PlaybackManager.playerDidFinishPlayingEpisode()`.
- Dreaming log status is surfaced through `Constants.Notifications.dreamingLogStatusChanged` and used by UI such as `EpisodeCell`.
- Dreaming settings and progress UI live under `podcasts/Dreaming/`, with navigation wired from `SettingsViewController`.

When working in this area, review:
- `podcasts/Dreaming/DreamingManager.swift`
- `podcasts/Dreaming/DreamingSettingsViewController.swift`
- `podcasts/Dreaming/DreamingProgressViewController.swift`
- `podcasts/EpisodeManager.swift`
- `podcasts/PlaybackManager.swift`
- `podcasts/EpisodeCell.swift`
- `podcasts/Constants.swift`
- `podcasts/SettingsViewController.swift`

## Adding New Swift Files to the Xcode Project

Every new `.swift` file placed under `podcasts/` (or any other compiled target directory) **must** also be registered in `podcasts.xcodeproj` or the build will silently ignore it. Use the `xcodeproj` gem (already available via Bundler) to do this from the command line:

```bash
bundle exec ruby - <<'RUBY'
require 'xcodeproj'
project = Xcodeproj::Project.open('podcasts.xcodeproj')

# Adjust the subpath to match where the file lives, e.g. 'podcasts/Dreaming'
group = project.main_group.find_subpath('podcasts/Dreaming', true)
file_ref = group.new_reference('NewFile.swift')

target = project.targets.find { |t| t.name == 'podcasts' }
target.source_build_phase.add_file_reference(file_ref)

project.save
puts "Registered NewFile.swift in podcasts target"
RUBY
```

Replace `'podcasts/Dreaming'` with the actual group path and `'NewFile.swift'` with the actual filename. Run this immediately after writing the file, then verify with `grep 'NewFile' podcasts.xcodeproj/project.pbxproj`.

**Watch target caveat:** `DreamingManager.swift` is compiled into both the main `podcasts` target and the `Pocket Casts Watch App` target. If code added to `DreamingManager.swift` references types that only exist in the main iOS target (e.g. `ManualEntryKind`), guard those additions with `#if !os(watchOS)`. The same applies to any other file shared between targets — check for duplicate build file entries in `project.pbxproj` before referencing iOS-only types.

## Practical Guidance

- Prefer project entry points and existing make targets over custom one-off commands.
- Treat `podcasts/Credentials/` and related build-phase scripts carefully; missing or replaced secrets can break local builds.
- If you change build, lint, formatting, resource generation, or protobuf behavior, verify the affected make target still works.
