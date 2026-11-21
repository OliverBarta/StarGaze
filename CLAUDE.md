# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

StarGaze is a SwiftUI iOS app (iPhone + iPad), currently at the Xcode new-project template stage: `StarGazeApp.swift` (the `@main` entry, one `WindowGroup`) and a placeholder `ContentView.swift`. The only third-party dependency is Auth0.swift (see below), and there are no test targets yet.

## Build

Single project, single target, single scheme (`StarGaze`). No workspace; one Swift package (Auth0.swift), resolved by Xcode.

```sh
# Build for the simulator without code signing
xcodebuild -project StarGaze.xcodeproj -scheme StarGaze \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO

# List simulators to pick a concrete -destination (needed for running or testing)
xcrun simctl list devices available
```

There is no test target, so `xcodebuild test` won't work until one is added in Xcode (File > New > Target > Unit Testing Bundle). After that, run a single test with `-only-testing:<TestTarget>/<TestClass>/<testMethod>`.

## Project configuration that affects code

- **Deployment target is iOS 26.2.** Use current SwiftUI/Observation APIs freely; no `#available` checks needed for anything older.
- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** and **`SWIFT_APPROACHABLE_CONCURRENCY = YES`**: every type is implicitly `@MainActor` unless marked otherwise. Background work has to opt out explicitly (`nonisolated`, `@concurrent`, or a separate actor).
- **Swift language mode is 5.0** (not 6), so strict-concurrency diagnostics show up as warnings, not errors.
- **The project uses file-system-synchronized groups** (`objectVersion = 77`). Any file created under `StarGaze/` is picked up by the target automatically. Don't hand-edit `project.pbxproj` to register new source files.
- Bundle ID: `com.oliver.StarGaze`.
- **Auth0 login** uses [Auth0.swift](https://github.com/auth0/Auth0.swift) 3.x (SPM, `Auth0` product). Note the 3.x API names: `logout(federated:)` (not `clearSession`), `credentialsManager.userProfile()` (not `.user`), and `store`/`clear` throw. Config is in `StarGaze/Auth0.plist` (`ClientId`, `Domain`; not secrets). Login uses a custom URL scheme callback, `com.oliver.stargaze://dev-egzorfokrbjlmaxi.us.auth0.com/ios/com.oliver.StarGaze/callback`, registered under URL Types in `StarGaze/Info.plist` (merged with the generated Info.plist). No Universal Links or Associated Domains. All auth logic lives in `Shared/Services/AuthService.swift`, injected into the environment by `StarGazeApp`.
