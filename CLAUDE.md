# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

StarGaze is a SwiftUI iOS app (iPhone + iPad) for stargazers. No third-party dependencies and no test targets yet.

- **Entry point:** `StarGaze/App/StarGazeApp.swift` currently launches `StargazingSpotsView` directly. `ContentView.swift` holds the intended `TabView` (Stars, Light Pollution, Friends, Collection) but isn't wired up.
- **Stargazing Spots** (`StarGaze/StargazingSpots/`), the most complete feature:
  - `StargazingSpotsView` is the screen: an edge-to-edge map, a bottom panel with tonight's summary, a time slider and the colour key. Tapping a numbered spot pin opens `SpotDetailView`. The navigation bar floats over the map with a layers menu and a reload button.
  - `LightPollutionMapView` wraps UIKit's `MKMapView` (SwiftUI `Map` can't draw custom image overlays) and draws light-pollution tiles, the cloud layer (the 9 × 9 forecast grid upscaled into one smooth, round-edged image by `CloudImage`), the search circle and spot pins.
  - `LightPollutionService` loads the light-pollution tiles. `findDarkSpots` picks the 3 best land spots within the search radius (`StargazingConfig.searchRadiusKm`, 25 km), ranked by darkness × cloud at the slider's hour, at least 10 km apart. The spots are re-picked when the forecast arrives and when the slider moves.
  - `TonightConditionsService` fetches the cloud forecast from Open-Meteo (free, no key) on a 9 × 9 grid with a 30-minute cache, and scores spots by darkness, cloud, Moon and twilight.
  - `StargazingModels.swift` has `SpotLocationProvider`: GPS via `CLLocationUpdate.liveUpdates()`, last fix saved in `UserDefaults` and used at launch until GPS answers.
  - Light-pollution data is bundled in `StargazingSpots/LightTiles/`: ~1,130 `.bin` tiles plus `index.json`, derived from the Falchi et al. 2016 atlas. The tile format is documented at the top of `LightPollutionService.swift`. A byte of 0 means water.
- **Star map** (`StarGaze/Features/StarMap/`): pick a sky photo; `GeminiService` asks Google Gemini to identify constellations, and `ConstellationView` draws them over the photo.
- **Collection** (`StarGaze/Features/Collection/`): constellation cards. **Friends** and **Light Pollution** (`Features/`) are placeholders.

### Secrets

`StarGaze/Config/Secrets.swift` (`enum Secrets { static let geminiAPIKey = ... }`) is gitignored and shared privately. A fresh clone won't build until it's created. Never commit it or print the key.

## Build

Single project, single target, single scheme (`StarGaze`). No workspace or Swift packages.

```sh
# Build for the simulator without code signing
xcodebuild -project StarGaze.xcodeproj -scheme StarGaze \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO

# List simulators to pick a concrete -destination (needed for running or testing)
xcrun simctl list devices available
```

To run in a simulator, build with `-destination "id=<udid>"`, then `xcrun simctl install <udid> <path>/StarGaze.app` and `xcrun simctl launch <udid> com.oliver.StarGaze`. For the Stargazing screen, grant location first (`xcrun simctl privacy <udid> grant location com.oliver.StarGaze`) and set one (`xcrun simctl location <udid> set <lat>,<lon>`).

There is no test target, so `xcodebuild test` won't work until one is added in Xcode (File > New > Target > Unit Testing Bundle). After that, run a single test with `-only-testing:<TestTarget>/<TestClass>/<testMethod>`.

## Project configuration that affects code

- **Deployment target is iOS 18.0** (the app target overrides the project-level 26.2). Anything newer, like iOS 26 MapKit APIs, needs an `#available` check.
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** and **`SWIFT_APPROACHABLE_CONCURRENCY = YES`**: every type is implicitly `@MainActor` unless marked otherwise. Background work has to opt out explicitly (`nonisolated`, `@concurrent`, or a separate actor).
- **Swift language mode is 5.0** (not 6), so strict-concurrency diagnostics show up as warnings, not errors.
- **The project uses file-system-synchronized groups** (`objectVersion = 77`). Any file created under `StarGaze/` is picked up by the target automatically. Don't hand-edit `project.pbxproj` to register new source files.
- **Location permission text** comes from the `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` build setting (the Info.plist is generated). Add other `NS…UsageDescription` keys the same way.
- **All features share one module**, so type names must be unique across folders. Stargazing Spots uses `SpotLocationProvider` and `SpotAstronomy` because StarMap already has `LocationProvider` and `Astronomy`.
- Bundle ID: `com.oliver.StarGaze`.
