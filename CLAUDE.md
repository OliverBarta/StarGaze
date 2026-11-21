# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

StarGaze is a SwiftUI iOS app (iPhone + iPad), built at Hack Western 13. It has four tabs: an AR star map that identifies constellations and records "discoveries", a light-pollution/cloud map that suggests stargazing spots, a Strava-style friends feed and leaderboard, and a collection of discovered constellation cards. See `README.md` for the product overview and data credits.

## Build

Single project, single target, single scheme (`StarGaze`). No workspace; one Swift package (Auth0.swift), resolved by Xcode.

```sh
# Build for the simulator without code signing
xcodebuild -project StarGaze.xcodeproj -scheme StarGaze \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO

# List simulators to pick a concrete -destination (needed for running or testing)
xcrun simctl list devices available
```

**The build needs `StarGaze/Config/Secrets.swift`**, which is gitignored. If it's missing, copy `Secrets.example.swift` (repo root) there; it defines `Secrets.geminiAPIKey`.

There is no test target and no linter, so `xcodebuild test` won't work until a test target is added in Xcode (File > New > Target > Unit Testing Bundle). After that, run a single test with `-only-testing:<TestTarget>/<TestClass>/<testMethod>`. Views have `#Preview`s, often with several states (e.g. `FriendsView` empty / loading / error via `MockFriendsDataSource` options).

## Project configuration that affects code

- **Deployment target is iOS 26.x.** Use current SwiftUI/Observation APIs freely; no `#available` checks needed for anything older.
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** and **`SWIFT_APPROACHABLE_CONCURRENCY = YES`**: every type is implicitly `@MainActor` unless marked otherwise. Background work has to opt out explicitly (`nonisolated`, `@concurrent`, or a separate actor). The light-pollution code marks its pure data types `nonisolated` for this reason.
- **Swift language mode is 5.0** (not 6), so strict-concurrency diagnostics show up as warnings, not errors.
- **The project uses file-system-synchronized groups** (`objectVersion = 77`). Any file created under `StarGaze/` is picked up by the target automatically, including resources. Don't hand-edit `project.pbxproj` to register new files.
- **Resources are mostly copied flat into the bundle**, so code looks them up by name with `Bundle.main.url(forResource:withExtension:)` (the light tiles try `subdirectory: "LightTiles"` first, then fall back to flat). Resource file names must be unique across the whole `StarGaze/` tree.
- **`StarGaze/Shared/Views/ProgressView.swift` shadows `SwiftUI.ProgressView`** inside the module. Write `SwiftUI.ProgressView` when you want the system spinner or progress bar.
- Bundle ID: `com.oliver.StarGaze`. Camera and location usage strings are set as `INFOPLIST_KEY_*` build settings.
- **Auth0 login** uses [Auth0.swift](https://github.com/auth0/Auth0.swift) 3.x (SPM, `Auth0` product). Note the 3.x API names: `logout(federated:)` (not `clearSession`), `credentialsManager.userProfile()` (not `.user`), and `store`/`clear` throw. Config is in `StarGaze/Auth0.plist` (`ClientId`, `Domain`; not secrets). Login uses a custom URL scheme callback, `com.oliver.stargaze://dev-egzorfokrbjlmaxi.us.auth0.com/ios/com.oliver.StarGaze/callback`, registered under URL Types in `StarGaze/Info.plist` (merged with the generated Info.plist). No Universal Links or Associated Domains.

## Architecture

Code is organized as `App/` (entry and root navigation), `Features/<Feature>/` (StarMap, LightPollution, Friends, Collection), and `Shared/` (models, services, data and views used by more than one feature). State uses `@Observable` classes injected with `.environment(...)`; there's no separate DI layer.

**App flow.** `StarGazeApp` creates `AuthService` (`Shared/Services/AuthService.swift`, which holds all auth logic) and injects it. `RootView` restores the session, then shows `SignInView` or `ContentView`. `ContentView` owns the `TabView` and the `DiscoveryStore`, injects the store into every tab, and overlays the set-completion cutscenes (`SetCutsceneView`, or `AurigaCutsceneView` for Auriga) on top of all tabs. When a cutscene finishes it switches to the Collection tab.

**Discoveries and sets** (`Shared/Data/DiscoveryStore.swift`). This is the core game state, saved to `UserDefaults` as JSON. `SkyScreen` calls `store.discover(name, place:)` when a constellation stays in view. Discovering checks the sets in `ConstellationSet.all` (`Features/StarMap/Models/ConstellationSets.swift`). When a set reaches `required` finds, the store stamps those discoveries and queues a `Completion` for `ContentView` to play. `store.cards` builds the `CaptureCardContent` list shown in Collection. `cutsceneOnEveryFind` and `testHero` are testing toggles and should stay `false`/`nil` when committed.

**Star map** (`Features/StarMap/`). `SkyScreen` → `SkySceneView`, a `UIViewRepresentable` around SceneKit. On devices that support `ARWorldTrackingConfiguration` it uses an `ARSCNView` aligned to gravity and true heading. In the simulator it shows a draggable virtual sky. `Astronomy`/`SkyModel` convert RA/Dec to alt/az for the current location and time. Catalog data comes from bundled JSON (`Data/constellations.json` and `stars.json` from d3-celestial). `SkyArt` loads `constellation-art.json`, which pins each Stellarium illustration (`Data/Art/art-*.jpg`) to three anchor stars. `GeminiService` fetches constellation descriptions from the Gemini REST API (`gemini-3.5-flash-lite`) and caches them in memory.

**Light pollution / spots** (`Features/LightPollution/`). `LightPollutionService` loads 5°×5° sky-brightness tiles: bundled `LightTiles/*.bin` first, then a disk cache, then an optional remote URL (`remoteBaseURL`, nil by default). The tile binary format is documented at the top of that file and must match the offline `make_light_tiles.py` preprocessing script, which is not in this repo. Keep the `Bortle` thresholds in sync with that script too. `TonightConditionsService` calculates sun and moon positions on the device and fetches cloud cover from Open-Meteo (no API key, 30-minute cache), then scores spots for tonight. `StargazingSpotsView` and `LightPollutionMapView` (MapKit) show the results, and `SpotDetailView` shows details for one spot.

**Friends** (`Features/Friends/`). MVVM: `FriendsViewModel` reads from the `FriendsDataSource` protocol. Only `MockFriendsDataSource` exists so far, and it's the default in `FriendsView.init`. A real backend should be a new conformer, with no view changes. `FriendStanding.ranked` counts each constellation once per friend per week, so data sources should return captures without removing duplicates.

**Shared cards.** `CaptureCardContent` + `CaptureCardView` render both Collection cards and friend-feed captures (`FriendCapture+CaptureCardContent.swift` adapts friend captures). Rarity and points come from `Rarity.forConstellation`. Images are resolved by name through the `ConstellationCatalog` protocol (`AssetConstellationCatalog`).
