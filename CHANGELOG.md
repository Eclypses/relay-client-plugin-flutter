# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]


## [5.0.0] - 2026-06-03

### Added
- `MteRelayClient` class — new primary V5 Dart API with typed request/response models (`RelayRequest`, `RelayResponse`, `RelayFileDownloadRequest`, `RelayFileUploadRequest`, `RelayClientSettings`, `RelayOperationEvent`)
- `MteRelayClient.events` stream (`Stream<RelayOperationEvent>`) replacing the V4 multi-stream callback pattern for all non-upload operations
- `MteRelayClient.getSettings()` and `updateSettings()` for typed relay settings read/write
- `MteRelayClient.startDownload()` for streamed file download directly to disk
- `MteRelayClient.repair()` for manual re-pairing
- `MteRelayClient.startRelaySse()` / `cancelRelaySse()` for Server-Sent Event stream support
- `MteRelayClient.cancelOperation()` to cancel in-progress operations
- `MteRelayClient.getKeepAliveDiagnostics()` for connection diagnostics
- Android relay dependency override support for local Maven/direct AAR usage (`mteRelayAndroidGroup`, `mteRelayAndroidArtifact`, `mteRelayAndroidVersion`, `mteRelayAndroidAarPath`)
- iOS local relay library override via `MTE_RELAY_IOS_PATH` environment variable or `mteRelayIosPath` property
- Expanded testing summary for finalized V5 validation status and runtime verification notes
- Repository pre-commit audit prompt at `.github/prompts/pre-commit-audit.prompt.md`
- README API reference coverage for `getPlatformVersion()` under a "Platform Metadata" section

### Changed
- **BREAKING:** Primary Dart client class is now `MteRelayClient`; `MteRelayClientPlugin` is retained for file uploads only
- **BREAKING:** `initializeRelay()` → `initialize()`
- **BREAKING:** `relayDataTask(Map)` → `send(RelayRequest)` returning typed `RelayResponse`
- **BREAKING:** `relayDownloadFile(Map)` → `startDownload(RelayFileDownloadRequest)` with `destinationPath`
- **BREAKING:** `rePair({url, pathnamePrefix})` → `repair(serverUrl, {pathnamePrefix})`
- **BREAKING:** `adjustRelaySettings({url, pairPoolSize})` → `updateSettings(serverUrl, RelayClientSettings)`
- **BREAKING:** `enableFileLogging({'url', 'isEnabled'})` → `enableFileLogging(bool)` (no URL, no Map)
- **BREAKING:** `readLogFile({'url'})` → `readLogFile()` (no args)
- **BREAKING:** `clearLogFile({'url'})` → `clearLogFile()` (no args)
- **BREAKING:** Request field `url` → `serverUrl` in all typed models
- **BREAKING:** Request field `body` → `bodyUtf8` / `bodyBase64` in `RelayRequest`
- **BREAKING:** Request field `downloadLocation` → `destinationPath` in `RelayFileDownloadRequest`
- **BREAKING:** `Result` / `NativeHttpResponse` response wrappers replaced by `RelayResponse`
- **BREAKING:** iOS minimum deployment target raised to 16.0
- Single import (`mte_relay_client_plugin.dart`) covers all V5 types; `mte_relay_response_model.dart` and `mte_relay_native_response.dart` no longer needed
- Migrated Android plugin bridge to V5-only relay usage (removed legacy reflection/fallback signature probing)
- Android settings bridge now uses `RelayClientSettings` and `getRelaySettings(serverUrl)` for typed read/write settings flows
- Updated iOS native bridge to V5 async/await relay APIs
- Updated method channel to dual-channel architecture (`mte_relay/methods` + `mte_relay/events`) for typed V5 operations alongside legacy channel
- Updated README to document V5 API throughout with a comprehensive "Migration from V4" section
- Updated `dev_docs/flutter-spm.md` quick-start guide for V5 with full breaking changes section
- Updated example app streaming behavior and multipart construction for stable V5 upload/download operation

### Fixed
- Fixed streamed upload bridge sequencing and stream lifecycle handling to prevent premature pipe closure
- Fixed streamed download request property handling to ensure non-empty `downloadPath` assignment for relay V5
- Fixed stream callback null-safety handling in Android bridge to avoid `NullPointerException` on null response payloads
- Fixed analyzer findings in example/test code by removing redundant nullable initialization and unused locals


## [4.5.0] - 2026-03-10

### Added
-

### Changed
- Migrated iOS Swift package dependency from `eclypses-aws-mte-relay-client-ios` to `mte-relay-client-ios` and updated to `4.6.0`
- Updated iOS plugin minimum deployment target to `iOS 16.0`
- Updated example app default relay server URL to `https://mte-relay-demo-relay-server.eclypses.com`

### Fixed
-


## [4.4.0] - 2026-03-05

### Added
- Comprehensive Dart test suite across response models, platform interface, method channel bridge, and public API delegation
- Reusable test fixtures and fake platform helpers under `test/fixtures` and `test/helpers`
- Testing guide in `dev_docs/TESTING_SUMMARY.md`

### Changed
- Azure pipeline aligned to shared plugin pattern: run analyze + tests with coverage on `develop` and `master`
- Release workflow script updated to also bump README git ref and include README in release commit set
- Dart SDK constraints normalized from dev SDK pins to stable-compatible constraints in root and example pubspec files

### Fixed
- Removed duplicate `4.3.0` section and duplicate reference entry in changelog
- Corrected malformed changelog release links (including `4.2.8`, `4.2.9`) and standardized tag link format
- Synced README dependency example version ref to current plugin version


## [4.3.0] - 2026-01-22

### Added
- Added dev_docs directory and release script

### Changed
- Enhanced README to be a comprehensive implementation guide, suitable for all experience levels

### Fixed
- Removed Pod-based files


## [4.2.11] - 2025-09-30

### Added 
-

### Changed
- Updated mte_relay_client_plugin.java to remove unneeded Override
- Updated pubspec.yaml to pull updated MteRelay library
- Updated Version number throughout

### Fixed
-

## [4.2.10] - 2025-09-05

### Added 
-

### Changed
- Updated mte_relay_client_plugin.java to remove unneeded Override
- Updated pubspec.yaml to pull updated MteRelay library
- Updated Version number throughout

### Fixed
-

## [4.2.9] - 2025-09-04

### Added
-

### Changed
- Updated to use Swift Package Manager instead of CocoaPods
- Updated Version number throughout

### Fixed
-

## [4.2.8] - 2025-09-03

### Added 
-

### Changed
- Updated to reference updated MteRelay for iOS
- Updated Version number throughout

### Fixed
-

## [4.2.7] - 2025-09-03

### Added 
- 

### Changed
- Updated mte_relay_client_plugin.podspec

### Fixed
-

## [4.2.6] - 2025-09-02

### Added 
-

## [4.2.5] - 2025-09-02

### Added 
-

### Changed
- Updated Version number in README.md

### Fixed
-

## [4.2.4] - 2025-09-02

### Added 
-

### Changed
- Updated Version number in pubspec.yaml

### Fixed
-

## [4.2.3] - 2025-08-27

### Added 
-

### Changed
- Updated Version number in pubspec.yaml
- Removed escape characters from Android Response Body Json
- Removed square brackets from Android Response Headers
- Upgraded iOS Relay Package which downgraded iOS Target from v16 to v14

### Fixed
-

## [4.2.2] - 2025-07-03

### Added 
-

### Fixed
-

## [4.2.1] - 2025-05-21

### Added 
-

### Changed
- Updated Version number in pubspec.yaml
- Removed escape characters from Android Response Body Json
- Removed square brackets from Android Response Headers
- Upgraded iOS Relay Package which downgraded iOS Target from v16 to v14

### Fixed
-

## [1.0.0] - Initial Release

### Added
- Initial Release. iOS plugin calls are working. Android not yet implemented.

[1.0.0]: https://github.com/Eclypses/mte-relay-client-flutter/releases/tag/v1.0.0
[4.2.1]: https://github.com/Eclypses/mte-relay-client-flutter/releases/tag/v4.2.1
[4.2.2]: https://github.com/Eclypses/mte-relay-client-flutter/releases/tag/v4.2.2
[4.2.3]: https://github.com/Eclypses/mte-relay-client-flutter/releases/tag/v4.2.3
[4.2.4]: https://github.com/Eclypses/mte-relay-client-flutter/releases/tag/v4.2.4
[4.2.5]: https://github.com/Eclypses/mte-relay-client-flutter/releases/tag/v4.2.5
[4.2.6]: https://github.com/Eclypses/mte-relay-client-flutter/releases/tag/v4.2.6
[4.2.7]: https://github.com/Eclypses/mte-relay-client-flutter/releases/tag/v4.2.7
[4.2.8]: https://github.com/Eclypses/mte-relay-client-flutter/releases/tag/v4.2.8
[4.2.9]: https://github.com/Eclypses/mte-relay-client-flutter/releases/tag/v4.2.9
[4.2.10]: https://github.com/Eclypses/mte-relay-client-flutter/releases/tag/v4.2.10
[4.2.11]: https://github.com/Eclypses/mte-relay-client-flutter/releases/tag/v4.2.11
[4.3.0]: https://github.com/Eclypses/mte-relay-client-flutter/releases/tag/v4.3.0

[4.4.0]: https://github.com/Eclypses/mte-relay-client-flutter/releases/tag/v4.4.0

[4.5.0]: https://github.com/Eclypses/mte-relay-client-flutter/releases/tag/v4.5.0
[5.0.0]: https://github.com/Eclypses/mte-relay-client-flutter/releases/tag/v5.0.0
