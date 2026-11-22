# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

StarGaze is a SwiftUI iOS app (iPhone + iPad), built at Hack Western 13. It's a citizen-science game: players collect constellations, and every find also measures light pollution, so together they build a real ground-level light-pollution map. See `README.md` for data credits.

How a find works:
1. The user points the phone at the sky. The Stars tab draws the real sky over the camera and identifies constellations from location, compass and motion.
2. Holding steady on a constellation fills a ring; once it's full, the capture button adds it to the collection.
3. Right after (real camera only), the app takes one long-exposure sky photo: "Hold still… 3·2·1", then the shutter. A set cutscene triggered by the find waits until the shutter has fired. The phone counts the stars in the photo, then Gemini checks its quality in the background (this doesn't block the next capture); nothing is saved yet.

**Identification is sensor-based (location + compass + motion), never Gemini.** Gemini only does photo quality control for sky readings.

Tabs:
- **Stars**: find and collect constellations.
- **Light Pollution**: satellite and (later) user-measured maps, and dark spots for tonight.
- **Friends**: feed of friends' finds and the weekly leaderboard.
- **Collection**: your finds, completed sets and stamps.

Backend: a teammate is building the Supabase database on another branch. Keep new data local and upload-ready; don't add Supabase code here.

## Build

Single project, single target, single scheme (`StarGaze`). No workspace; one Swift package (Auth0.swift), resolved by Xcode.

```sh
# Build for the simulator without code signing
xcodebuild -project StarGaze.xcodeproj -scheme StarGaze \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO

# List simulators to pick a concrete -destination (needed for running or testing)
xcrun simctl list devices available
```

**The build needs `StarGaze/Config/Secrets.swift`**, which is gitignored. If it's missing, copy `Secrets.example.swift` (repo root) there; it defines `Secrets.geminiAPIKey`, `supabaseURL` and `supabaseKey`.

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

**Discoveries and sets** (`Shared/Data/DiscoveryStore.swift`). This is the core game state, saved to `UserDefaults` as JSON. `SkyScreen` calls `store.discover(name, place:)` when the user captures a constellation whose ring is full. Discovering checks the sets in `ConstellationSet.all` (`Features/StarMap/Models/ConstellationSets.swift`). When a set reaches `required` finds, the store stamps those discoveries and queues a `Completion` for `ContentView` to play. `store.cards` builds the `CaptureCardContent` list shown in Collection. `cutsceneOnEveryFind` and `testHero` are testing toggles and should stay `false`/`nil` when committed.

**Star map** (`Features/StarMap/`). `SkyScreen` → `SkySceneView`, a `UIViewRepresentable` around SceneKit. On devices that support `ARWorldTrackingConfiguration` it uses an `ARSCNView` aligned to gravity and true heading. In the simulator it shows a virtual sky you can drag; this is a silent developer fallback, and the UI always says "Point your phone at the sky". Targeting lives in `Features/StarMap/Targeting/`: `TargetFigure` precomputes each constellation's stars, lines and outline (convex hull) when the sky is built, `ConstellationTargeting` scores the view direction against that shape (0 inside the outline, size-aware tolerance), and `TargetTracker` adds hysteresis and dwell progress that drains instead of resetting. A full ring only marks the target ready; the capture button (`captureCount` → `Coordinator.capture()`) collects it. The sky photo lives in `Features/StarMap/SkyReading/`: `SkyPhotoSession` runs countdown → `arPaused` (SkySceneView pauses its ARSession so the camera is free) → `SkyPhotoCapturer` (AVFoundation, long exposure, high ISO, focus near infinity, no multi-frame fusion) → resume AR. `MotionRecorder` logs attitude and rotation during the exposure. `DiscoveryStore.holdsCutscenes` delays set cutscenes until the shutter fires (`ContentView` shows `store.cutsceneToPlay`). After the shot, `StarDetector` (pure, Accelerate) finds stars: `LuminanceImage` converts to linear gray and halves the photo with hot-pixel-rejecting 2×2 binning (second-brightest of each block), then background (cell medians) is subtracted and point-like peaks above k·σ are kept; large, clipped, elongated and edge blobs are rejected. It reports the count and a relative sky glow (background per second per ISO 100, comparable on one phone model only). Then `GeminiService.analyzeSky(_:context:)` gets the upright photo plus a `SkyAnalysisContext` (target name, its brightest stars from `TargetStarCatalog`, the detected count) and acts as a quality filter: a clear bright city sky with few stars is valid, and `SkyReadingIssue.issues(from:)` turns clouds, lights in frame, haze, blur, lens problems or a non-sky photo into blocking issues (partial cloud only lowers confidence). All camera, detection and Gemini numbers are in `SkyReadingTuning`. In DEBUG, Profile has a toggle to save the full photos to Photos. All thresholds are in `TargetingTuning`. Discovered constellations can be targeted (name shown) but not collected. `Astronomy`/`SkyModel` convert RA/Dec to alt/az for the current location and time. Catalog data comes from bundled JSON (`Data/constellations.json` and `stars.json` from d3-celestial). `SkyArt` loads `constellation-art.json`, which pins each Stellarium illustration (`Data/Art/art-*.jpg`) to three anchor stars. Tapping a constellation opens `ConstellationInfoView`, whose text comes from `Data/constellation-info.json` via `ConstellationInfoCatalog` (no Gemini). `GeminiService` (`Shared/Services/`, Gemini REST API, `gemini-3.5-flash-lite`) has one job: `analyzeSky(_:)`, the photo quality check that returns a validated `SkyAnalysis` (JSON-only via `responseSchema`, image downscaled to 1024px). `FindLevel(analysis:)` is the single Spotted/Located rule. Profile → "Analyze a sky photo" (`SkyReadingTestView`) runs the check on library photos for testing and indoor demos; library photos never count as map measurements.

**Light pollution / spots** (`Features/LightPollution/`). `LightPollutionService` loads 5°×5° sky-brightness tiles: bundled `LightTiles/*.bin` first, then a disk cache, then an optional remote URL (`remoteBaseURL`, nil by default). The tile binary format is documented at the top of that file and must match the offline `make_light_tiles.py` preprocessing script, which is not in this repo. Keep the `Bortle` thresholds in sync with that script too. The tiles are no longer used for spots: `ReadingSpots` (`LightReadingsHeatmap.swift`) picks them from the `light_readings` heatmap, mapping strength 0…1 linearly to SQM 22…18. `TonightConditionsService` calculates sun and moon positions on the device and fetches cloud cover from Open-Meteo (no API key, 30-minute cache), then scores spots for tonight. `StargazingSpotsView` and `LightPollutionMapView` (MapKit) show the results, and `SpotDetailView` shows details for one spot.

**Friends** (`Features/Friends/`). MVVM: `FriendsViewModel` reads from the `FriendsDataSource` protocol. `ContentView` passes `SupabaseFriendsDataSource`; `MockFriendsDataSource` is the default in `FriendsView.init` and drives the previews. `FriendStanding.ranked` counts each constellation once per friend per week, so data sources should return captures without removing duplicates.

**Supabase** (`Shared/Services/SupabaseService.swift`, schema in `supabase/schema.sql`). Plain `URLSession` calls to PostgREST, no SDK. Auth is Auth0 via Supabase Third-Party Auth: `AuthService` requests the `https://stargaze-api` audience so the access token is a JWT, and RLS reads the Auth0 `sub` (text, not a UUID) through `requesting_user_id()`. `ContentView.startSharing()` creates the profile (auto-generated username), re-uploads all local discoveries (deduped by a unique constraint), and hooks `DiscoveryStore.onDiscover` to upload new finds. Follows are one-way; the `feed` view returns captures from followed users.

**Shared cards.** `CaptureCardContent` + `CaptureCardView` render both Collection cards and friend-feed captures (`FriendCapture+CaptureCardContent.swift` adapts friend captures). Rarity and points come from `Rarity.forConstellation`. Images are resolved by name through the `ConstellationCatalog` protocol (`JSONConstellationCatalog`, which loads the PNG named by each constellation's `image` in `constellation-info.json`).
