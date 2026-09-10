# ServiceHub Instructions

## Project Overview

ServiceHub is a native macOS local service management and supervision tool built with Swift 6 and SwiftUI.

- **Stack**: macOS 13+, Swift 6, SwiftUI, Swift Package Manager (SPM), Yams (YAML parsing).
- **Package Manifest**: `Package.swift`.

## Architecture & Layout

- `Sources/ServiceHub/App/`: Application entry point (`ServiceHubApp.swift`) and window management.
- `Sources/ServiceHub/Core/`:
  - `Supervisor.swift`: Core supervision engine (process lifecycle, auto-restart, circuit breaker/flap protection).
  - `ProcessRunner.swift`: Subprocess execution, environment injection, and graceful POSIX signal termination (`SIGTERM`/`SIGKILL`).
  - `PreconditionChecker.swift`: Startup conditions (network reachability, Wi-Fi SSID, power/battery).
  - `HealthProbe.swift`: HTTP/TCP health checks.
  - `LogTail.swift`: Non-blocking async log tailing and circular buffer.
  - `BrewScanner.swift`, `DockerScanner.swift`, `AppPickerHelper.swift`: Integration discovery.
  - `Localization.swift`: Dual-language (zh-CN / en) support.
- `Sources/ServiceHub/Models/`: Data structures and state definitions (`Service.swift`).
- `Sources/ServiceHub/Store/`: Local persistence (`ServiceStore.swift`, YAML storage).
- `Sources/ServiceHub/Views/`: SwiftUI views (Main window, card grid, list, menu bar extra, log console, design system).

## Verification Commands

Run targeted compile checks and tests using the Swift Package Manager CLI:

```bash
swift build
swift test
```
Do not launch the running application GUI or initiate active service processes during automated verification.

## Engineering Standards

- **Swift Concurrency**: Strictly adhere to Swift 6 concurrency models. Ensure UI state updates run on `@MainActor`, and types crossing concurrency boundaries adhere to `Sendable`.
- **Subprocess Safety**: Always clean up child process pipes and handles; never leak zombie processes or detached process groups upon termination.
- **macOS Design System**: Use `DesignSystem.swift` styles, icons, and spacing tokens to maintain consistent macOS HIG appearance across light/dark modes.
- **Dual Language**: Every user-facing UI text must be defined through `Localization.swift` for both Chinese and English.
