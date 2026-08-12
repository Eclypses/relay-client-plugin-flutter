<center>
<img src="Eclypses.png" style="width:50%;" alt="Eclypses Logo"/>
</center>

<div align="center" style="font-size:40pt; font-weight:900; font-family:arial; margin-top:50px;" >
MteRelay Client Flutter Plugin (SPM) </div>
<br>

### This Flutter plugin provides plug-and-play MTE integration for iOS/Swift and Android/Java Flutter applications, allowing quick integration with very minimal code changes. This Client Plugin requires a corresponding MteRelay Server API to receive the encoded requests and relay them onto the original API.

---

## 📑 Table of Contents

- [Overview](#overview)
- [V5 Summary](#v5-summary)
- [Before You Begin](#before-you-begin)
- [Add MteRelay Client Flutter Plugin to your application](#add-mterelay-client-flutter-plugin-to-your-application)
- [Response Handling](#response-handling)
- [API Reference](#api-reference)
- [Migration from V4](#migration-from-v4)
- [Troubleshooting](#troubleshooting)
- [Contact Eclypses](#contact-eclypses) 
<br><br>

## Overview 
When you have integrated this Plugin into your Flutter application and have set up and configured the corresponding MteRelay Server API, your client application will make its network calls just as before except that they are now routed through the MteRelay plugin. 

There, the Request is inspected and the relevant information captured. The MteRelay mobile client checks for a corresponding MteRelay Server and if not found, returns an error. However, if the server IS found, a new request is created, the original data is encoded with MTE and sent to the MteRelay server where is it decoded. 

From there, the original request is sent on to the original destination API. Any response will follow the same path in reverse.
<br>

This project is a starting point for a Flutter [plug-in package](https://flutter.dev/to/develop-plugins), a specialized Eclypses MteRelay Client package that includes platform-specific implementation code for Android and iOS. To be useful, this Plugin requires licensed access to an MteRelay server instance. 

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

<br>

## V5 Summary

V5 is a breaking refactor at both the Dart API and native bridge levels.

**Dart API changes:**
- Primary client class is now `MteRelayClient` with typed request/response models (`RelayRequest`, `RelayResponse`, `RelayClientSettings`, etc.).
- `MteRelayClientPlugin` is retained for file uploads only — the chunk-based streaming path requires it.
- Method renames: `initializeRelay()` → `initialize()`, `relayDataTask()` → `send()`, `relayDownloadFile()` → `startDownload()`, `rePair()` → `repair()`, `adjustRelaySettings()` → `updateSettings()`.
- Logging no longer takes a URL or Map argument: `enableFileLogging(bool)`, `readLogFile()`, `clearLogFile()`.
- A single `events` stream (`Stream<RelayOperationEvent>`) replaces the V4 multi-stream callback pattern for all non-upload operations.
- Single import: `mte_relay_response_model.dart` and `mte_relay_native_response.dart` are no longer needed.

**Native bridge changes (Android):**
- Relay initialization uses `Relay.getInstance(context)` (no init-time listener overload).
- Re-pair callbacks are passed to `rePairWithRelayServer(...)`.
- Android settings use `RelayClientSettings` and `getRelaySettings(serverUrl)` for typed read/write flows.
- Logging uses static APIs: `enableFileLogging(Boolean)`, `readLogFile()`, and `clearLogFile()`.
- Android relay `clientId` persistence is handled by the native relay library.

If you are upgrading from older integration patterns, see [Migration from V4](#migration-from-v4).

<br>

## Before You Begin

> 💡 **Alternative Version:** If your project requires CocoaPods for iOS dependency management, use the [CocoaPods version of this plugin](https://github.com/Eclypses/mte-relay-client-flutter-pod) instead.

Ensure you have the following ready before integrating this plugin:

- [ ] **MteRelay Server Access** - A running MteRelay server instance with your server URL
- [ ] **Flutter SDK** - Latest stable version installed (\`flutter --version\` to check)
- [ ] **Xcode** - Latest version for iOS development (macOS only)
- [ ] **Android Studio** - For Android development with SDK tools installed

> 💡 **Tip:** Run \`flutter doctor\` to verify your development environment is properly configured.

<br>

## Add MteRelay Client Flutter Plugin to your application

### Step 1: Add the Plugin Dependency

This MteRelay Client Flutter Plugin is not published on pub.dev. Add it directly from GitHub by editing your \`pubspec.yaml\` file:

> ⚠️ **Important:** YAML indentation is critical! Use exactly 2 or 4 spaces (be consistent), never tabs.

\`\`\`yaml
dependencies:
  flutter:
    sdk: flutter
  mte_relay_client_plugin:
    git:
      url: https://github.com/Eclypses/relay-client-plugin-flutter.git
      ref: v5.0.0
\`\`\`

> ⚠️ **iOS Requirement:** This plugin requires iOS 16.0 or greater. In your Xcode project, search for \`IPHONEOS_DEPLOYMENT_TARGET\` and ensure it is set to 16.0 or higher in all locations.

### Step 2: Install Dependencies

In a terminal at the root directory of your project:

\`\`\`bash
flutter pub get
\`\`\`

This downloads the MteRelay Client Plugin to your project.

### Android Pre-Release Relay Library Override

If you need to consume a non-released Android relay build (for example `v5-refactor-interceptor`), this plugin supports Gradle property overrides.

Add one of these approaches in your build environment:

1. Use `mavenLocal()` artifact coordinates:

```properties
# Example values (set to the coordinates produced by your local publish)
mteRelayAndroidGroup=com.eclypses
mteRelayAndroidArtifact=eclypses-aws-mte-relay-client-android-release
mteRelayAndroidVersion=5.0.0-SNAPSHOT
```

2. Use a direct local AAR path:

```properties
mteRelayAndroidAarPath=/absolute/path/to/eclypses-aws-mte-relay-client-android-release.aar
```

You can place these in your Android Gradle properties or pass them as `-P` arguments at build time.

### iOS Local Relay Library Override

If you need to test this plugin against a local checkout of `mte-relay-client-ios`, the Swift package manifest now supports a local path override.

Use one of these approaches:

1. Set an environment variable before opening/building the iOS project:

```bash
export MTE_RELAY_IOS_PATH=/absolute/path/to/mte-relay-client-ios
```

2. Or add a property to a `local.properties` file in this repo, the `ios/` folder, or the `ios/mte_relay_client_plugin/` folder:

```properties
mteRelayIosPath=/absolute/path/to/mte-relay-client-ios
```

When the override is set, the plugin's `Package.swift` will use `.package(path: ...)` instead of the remote Git dependency.

If Xcode has already resolved the remote package, refresh package resolution after setting the override.

### Step 3: Import the Plugin

In the file where you'll use the MteRelay plugin, add these imports:

\`\`\`dart
import 'dart:convert';           // For JSON encoding/decoding
import 'dart:typed_data';        // For Uint8List handling
import 'package:flutter/services.dart';  // For PlatformException
import 'package:mte_relay_client_plugin/mte_relay_client_plugin.dart';
\`\`\`

### Step 4: Create Client Instances

\`\`\`dart
// Primary client for all standard operations
final _relay = MteRelayClient();

// Only needed for file uploads — see File Stream Upload
final _plugin = MteRelayClientPlugin();
\`\`\`

### Step 5: Initialize the Relay

When your class is instantiated, subscribe to the events stream and initialize the relay.

\`\`\`dart
@override
void initState() {
  super.initState();
  _relay.events.listen(_handleRelayEvent);
  initializeRelay();
}

void _handleRelayEvent(RelayOperationEvent event) {
  // Handle typed events for HTTP, download, and SSE operations.
  // File upload events arrive via MteRelayClientPlugin streams — see File Stream Upload.
}

Future<void> initializeRelay() async {
  try {
    await _relay.initialize();
  } on PlatformException {
    // Handle initialization failure
  }
}
\`\`\`

### Step 6: Make API Calls

Create arguments and call Plugin methods. Here's a sample POST request:

\`\`\`dart
// This is a sample POST request
Future<void> login() async {
  try {
    final request = RelayRequest(
      serverUrl: 'https://your-relay-server.com',
      route: '/api/login',       // This route WILL be encrypted
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      headersToEncrypt: ['Content-Type', 'Authorization'],
      bodyUtf8: jsonEncode({'email': 'user@example.com', 'password': 'password!'}),
      // pathnamePrefix: '/api/v1',  // Optional: unencrypted prefix
    );

    final response = await _relay.send(request);
\`\`\`

---

## Response Handling

`_relay.send()` returns a typed `RelayResponse`. All response data, headers, and errors are available as named fields.

`RelayResponse` provides:
- \`success\` - Boolean indicating if the request succeeded
- \`statusCode\` - HTTP status code (e.g., 200, 404)
- \`headers\` - Response headers as \`Map<String, List<String>>\`
- \`bodyUtf8\` - UTF-8 body string, if present
- \`bodyBase64\` - Base64-encoded body, if present
- \`errorMessage\` - Error description if the request failed
- \`decodeBodyBase64ToUtf8()\` - Convenience method to decode a base64 body to UTF-8

### Complete Example

\`\`\`dart
Future<void> login() async {
  try {
    final request = RelayRequest(
      serverUrl: relayServerUrl,
      route: '/api/login',
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      headersToEncrypt: ['Content-Type'],
      bodyUtf8: jsonEncode({'email': 'user@example.com', 'password': 'P@ssw0rd!'}),
    );

    final response = await _relay.send(request);

    if (response.success) {
      final json = jsonDecode(response.bodyUtf8!);
      print('Login successful: \$json');
    } else {
      print('Login failed: \${response.errorMessage}');
    }

  } on PlatformException catch (e) {
    print('Platform error: \${e.message}');
  } catch (error) {
    print('Unexpected error: \$error');
  }
}
\`\`\`

---

## API Reference

### Platform Metadata

Use this helper for quick diagnostics (for example, validating method-channel connectivity):

```dart
Future<void> showPlatformVersion() async {
  try {
    final version = await _plugin.getPlatformVersion();
    print('Platform version: ${version ?? "unknown"}');
  } catch (error) {
    print('Failed to read platform version: $error');
  }
}
```

### File Stream Upload

For large file uploads, use the chunk-based streaming pattern via `MteRelayClientPlugin`. The native relay library requests data one chunk at a time via a callback, and each chunk is encrypted as it is written — the file is never read entirely into memory.

Set up the listeners **before** calling `relayUploadFile`.

\`\`\`dart
// Sample FileStream Upload
// See the Example project in this plugin for complete implementation including MultipartHelper class
Future<void> uploadFileStream(String filesize) async {
  File file = await getFileToUpload(filesize);  // Your method to get the file
  String filename = file.path.split(Platform.pathSeparator).last;

  // MultipartHelper is provided in the Example project's lib/multipart_helper.dart
  builder = MultipartHelper(filename);

  String contentTypeHeader =
      'multipart/form-data; boundary=\${builder.boundary}';
  int contentLength = await builder.calculateContentLength(file);

  // Must be set up before relayUploadFile is called
  _plugin.relayRequestChunksStream.listen((streamID) async {
    final fileStream = file.openRead();
    await for (final chunk in fileStream) {
      await _plugin.sendChunk({
        'streamID': streamID,
        'data': Uint8List.fromList(chunk),
      });
    }
    await _plugin.closeStream({'streamID': streamID});
  });

  _plugin.relayStreamResponseStream.listen((args) {
    final success = args['success'] as bool;
    final statusCode = args['statusCode'] as int;
    // Handle upload result
  });

  await _plugin.relayUploadFile({
    'url': relayServerUrl,
    'pathnamePrefix': null,  // Optional: unencrypted path prefix
    'route': '/api/files/upload',  // This route WILL be encrypted
    'method': 'POST',
    'headers': {
      'Content-Type': contentTypeHeader,
      'Content-Length': contentLength.toString(),
      'Content-Transfer-Encoding': 'binary',
    },
    // Keep multipart framing headers in clear for reliable server parsing.
    'headersToEncrypt': const <String>[],
  });
}
\`\`\`

> 💡 **Note:** For streaming uploads, avoid encrypting multipart framing headers (`Content-Type`, `Content-Length`, `Content-Transfer-Encoding`).

### File Stream Download

The file is written directly to disk — it is never buffered in memory. Progress and completion arrive via `_relay.events`.

\`\`\`dart
// Sample FileStream download
Future<void> downloadFileStream() async {
  String filename = 'example.pdf';
  final urlEncodedFilename = Uri.encodeComponent(filename);
  final destinationPath = await getDownloadLocation(filename);  // Your method to get save path

  try {
    final request = RelayFileDownloadRequest(
      serverUrl: relayServerUrl,
      route: '/api/files/download/stream/\$urlEncodedFilename',
      destinationPath: destinationPath,  // Required local writable file path
      headers: {'Content-Type': 'application/json'},
      headersToEncrypt: ['Content-Type'],
    );

    final operationId = await _relay.startDownload(request);
    // Progress and completion arrive via _relay.events (downloadProgress, downloadCompleted, downloadError)
  } catch (error) {
    print('Download failed: \$error');
  }
}
\`\`\`

### Manual Re-Pairing

If a network call fails due to an MteRelay issue, automatic re-pair/retry occurs once. Use this method for manual re-pairing:

\`\`\`dart
Future<void> repair() async {
  try {
    await _relay.repair(relayServerUrl);
    // With optional pathname prefix:
    // await _relay.repair(relayServerUrl, pathnamePrefix: '/prefix');
  } catch (error) {
    print('Re-pair failed: \$error');
  }
}
\`\`\`

### Relay Settings

Read and update relay settings using `RelayClientSettings`. Call `updateSettings` right after `initialize()` to apply custom configuration at startup.

\`\`\`dart
Future<void> configureSettings() async {
  try {
    // Read current settings
    final current = await _relay.getSettings(serverUrl: relayServerUrl);

    // Apply updated settings
    final updated = RelayClientSettings(
      minPairs: 1,
      basePairs: 3,
      maxPairs: 6,
      keepAliveIntervalSeconds: 300,
      acquisitionWaitTime: 5.0,
    );
    await _relay.updateSettings(relayServerUrl, updated);
  } catch (error) {
    print('Failed to update settings: \$error');
  }
}
\`\`\`

> 💡 **Note:** Updating settings triggers an automatic re-pair so future transmissions use the new configuration.

### Native Logging

Enable file logging for debugging MteRelay operations:

\`\`\`dart
// Enable or disable file logging
await _relay.enableFileLogging(true);

// Read the current log file contents
final logs = await _relay.readLogFile();
print('Log contents:\n\$logs');

// Clear the log file
await _relay.clearLogFile();
\`\`\`

### clientId Persistence (Android)

Current Android relay library versions persist and restore `clientId` internally.
Do not add Flutter-side clientId persistence workarounds unless you have a platform-specific requirement outside standard relay initialization.

---

## Migration from V4

This plugin now targets V5-only behavior at both the Dart and native bridge levels. Legacy compatibility paths were removed.

### Dart API Changes

| V4 | V5 |
|---|---|
| `MteRelayClientPlugin` (primary) | `MteRelayClient` (primary); `MteRelayClientPlugin` for uploads only |
| `initializeRelay()` | `initialize()` |
| `relayDataTask(Map args)` | `send(RelayRequest)` |
| `relayDownloadFile(Map args)` | `startDownload(RelayFileDownloadRequest)` |
| `rePair({url, pathnamePrefix})` | `repair(serverUrl, {pathnamePrefix})` |
| `adjustRelaySettings({url, pairPoolSize})` | `updateSettings(serverUrl, RelayClientSettings)` |
| `enableFileLogging({'url': ..., 'isEnabled': bool})` | `enableFileLogging(bool)` |
| `readLogFile({'url': ...})` | `readLogFile()` |
| `clearLogFile({'url': ...})` | `clearLogFile()` |
| Multiple callback streams | Single `events` stream (`Stream<RelayOperationEvent>`) |
| `'url'` field in request args | `serverUrl` field in typed model |
| `'body'` field in request args | `bodyUtf8` or `bodyBase64` in `RelayRequest` |
| `'downloadLocation'` field | `destinationPath` in `RelayFileDownloadRequest` |
| `Result.fromMap(response)` | `RelayResponse` returned directly from `send()` |
| Two imports required | Single import: `mte_relay_client_plugin.dart` |

### 1) Relay Initialization

**Before (legacy pattern)**
\`\`\`java
Relay.getInstance(context, relayResponseListener)
\`\`\`

**Now (V5)**
\`\`\`java
Relay.getInstance(context)
\`\`\`

### 2) Re-Pair Flow

**Before**
- Listener may have been supplied at `getInstance(...)` time.

**Now (V5)**
- Pass callbacks to `rePairWithRelayServer(...)` overloads.
- Flutter API:
\`\`\`dart
await _relay.repair(relayServerUrl);
\`\`\`

### 3) Adjust Relay Settings

**Before**
- Older integrations often tuned multiple knobs (stream chunk size, pair persistence, etc.).

**Now (V5)**
- Use typed `RelayClientSettings` to configure all settings fields.
- `serverUrl` is required.

\`\`\`dart
final settings = RelayClientSettings(
  minPairs: 1,
  basePairs: 3,
  maxPairs: 6,
  keepAliveIntervalSeconds: 300,
  acquisitionWaitTime: 5.0,
);
await _relay.updateSettings(relayServerUrl, settings);
\`\`\`

### 4) Logging API

Native Android uses static methods internally:

\`\`\`java
Relay.enableFileLogging(Boolean)
Relay.readLogFile()
Relay.clearLogFile()
\`\`\`

Dart API — no URL or Map argument, no return value on enable/clear:

\`\`\`dart
await _relay.enableFileLogging(true);
final logs = await _relay.readLogFile();
await _relay.clearLogFile();
\`\`\`

### 5) Streaming Upload/Download Notes

- Upload should keep multipart framing headers unencrypted.
- Download requires a non-empty writable `downloadLocation` path.
- The Flutter stream-chunk callback path should write chunks and then close the stream in order.

### 6) Removed Legacy Assumptions

- No host-list compatibility layer.
- No V4 helper compatibility shims.
- No Android reflection-based fallback to older relay signatures.

---

## Troubleshooting

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| \`PlatformException\` | Native code issue | Check that iOS/Android native setup is complete |
| \`Failed to initialize Relay\` | Server unreachable | Verify your \`relayServerUrl\` is correct and server is running |
| \`MteRelay server not found\` | Pairing failed | Check network connectivity and server configuration |
| Build fails on iOS | Deployment target too low | Set \`IPHONEOS_DEPLOYMENT_TARGET\` to 16.0 or higher in Xcode |

### Need More Help?

Refer to the **Example project** included in this plugin for complete, working implementations of all features.

---

<div style="page-break-after: always; break-after: page;"></div>

# Contact Eclypses

<p align="center" style="font-weight: bold; font-size: 20pt;">Email: <a href="mailto:info@eclypses.com">info@eclypses.com</a></p>
<p align="center" style="font-weight: bold; font-size: 20pt;">Web: <a href="https://www.eclypses.com">www.eclypses.com</a></p>
<p align="center" style="font-weight: bold; font-size: 20pt;">Chat with us: <a href="https://developers.eclypses.com/dashboard">Developer Portal</a></p>
<p style="font-size: 8pt; margin-bottom: 0; margin: 100px 24px 30px 24px; " >
<b>All trademarks of Eclypses Inc.</b> may not be used without Eclypses Inc.'s prior written consent. No license for any use thereof has been granted without express written consent. Any unauthorized use thereof may violate copyright laws, trademark laws, privacy and publicity laws and communications regulations and statutes. The names, images and likeness of the Eclypses logo, along with all representations thereof, are valuable intellectual property assets of Eclypses, Inc. Accordingly, no party or parties, without the prior written consent of Eclypses, Inc., (which may be withheld in Eclypses' sole discretion), use or permit the use of any of the Eclypses trademarked names or logos of Eclypses, Inc. for any purpose other than as part of the address for the Premises, or use or permit the use of, for any purpose whatsoever, any image or rendering of, or any design based on, the exterior appearance or profile of the Eclypses trademarks and or logo(s).
</p>
