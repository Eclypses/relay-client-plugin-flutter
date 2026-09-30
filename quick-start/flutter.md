---
title: MTE Relay Client for Flutter
sidebar_label: Flutter
description: An MTE Relay HTTP client plugin for Flutter applications (iOS & Android).
---

![Latest Release](https://img.shields.io/github/v/release/Eclypses/relay-client-plugin-flutter?style=flat-square)

## Introduction

This Flutter plugin provides the Eclypses MTE Relay Client for iOS and Android. It relays your ordinary HTTP requests to your backend through an MTE Relay server, transparently encrypting them with MTE (including Kyber-512 post-quantum key exchange). You must have access to an MTE Relay server instance. [More Info](https://eclypses.com/mte-technology/amazon-web-services-aws/)

**Purpose of the Relay Client:**

- Securely relay HTTP requests to your backend with MTE encryption
- Protect sensitive headers and bodies in transit
- Buffered request/response, long-lived streaming, and chunked file uploads
- Drop-in shaped: `RelayHttpClient` is an `http.Client`, so existing `package:http` code keeps working

:::tip Comprehensive Documentation
This guide provides a quick-start for experienced developers. For detailed examples, streaming/upload APIs, troubleshooting, and in-depth explanations, see the **[complete README on GitHub](https://github.com/Eclypses/relay-client-plugin-flutter/blob/main/README.md)**.
:::

## Prerequisites

- Flutter SDK (stable channel)
- iOS 16.0+ / Android SDK 28+
- Xcode 15.0+ (the plugin's Swift package needs Swift 5.9)
- Access to an MTE Relay server instance

## Installation

Add to your `pubspec.yaml` (the Dart package is `mte_relay`):

```yaml
dependencies:
  mte_relay:
    git:
      url: https://github.com/Eclypses/relay-client-plugin-flutter.git
      ref: v5.3.0
```

Run `flutter pub get`.

### iOS Setup (Swift Package Manager)

The plugin uses Swift Package Manager to resolve the iOS `Relay` dependency automatically from its `Package.swift`. iOS 16.0 is the minimum: set `IPHONEOS_DEPLOYMENT_TARGET` to 16.0 in Build Settings — on the Runner **project**, where the Flutter template sets it, and on the Runner target too if it overrides the value.

### Android Setup

Ensure `minSdk` is set to 28 or higher in `android/app/build.gradle.kts`.

## If you already use `package:http`

If your code already uses `package:http`, swap in `RelayHttpClient` and change nothing else —
it returns the same `http.Response` / `http.StreamedResponse` types. No setup call is needed;
the first request initializes the relay for you:

```dart
import 'package:mte_relay/mte_relay.dart';

// was: final client = http.Client();
final client = RelayHttpClient();
final res = await client.post(
  Uri.parse('https://your-relay-server.com/api/login'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({'email': 'user@example.com', 'password': 'P@ssw0rd!'}),
); // http.Response
```

That is the whole integration: point the URL at your relay server and keep your existing
status checks, decoding and error handling. Failures, the relay's own included, arrive as
`http.ClientException`. Skip the Setup section below — it is for the typed API.

## Setup (typed API)

For per-call streaming, file transfer or operation events. Import the package and create the
client. `MteRelayClient` is the typed interface;
`initialize()` validates the MTE license (pairing happens automatically on the first request).

```dart
import 'dart:convert';
import 'package:flutter/services.dart'; // For PlatformException
import 'package:mte_relay/mte_relay.dart';

class YourClass {
  final _relay = MteRelayClient();

  Future<void> init() async {
    // Optional: observe typed operation events (HTTP, download, SSE)
    _relay.events.listen((event) {
      // RelayOperationEvent — observability only
    });

    try {
      await _relay.initialize();
    } on PlatformException {
      // Handle initialization / license failure
    }
  }
}
```

## Usage

### Buffered Request/Response

Point `serverUrl` at your **MTE Relay server**; `route` is the path on your backend (always
encrypted). `send()` returns a typed `RelayResponse`.

```dart
Future<void> login() async {
  try {
    // `.text` takes a String body; the plain constructor takes `Uint8List`.
    final request = RelayRequest.text(
      serverUrl: 'https://your-relay-server.com',
      route: '/api/login',                     // the route is always encrypted
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': 'user@example.com', 'password': 'P@ssw0rd!'}),
      // pathnamePrefix: '/api/v1',            // optional, unencrypted prefix
    );

    final response = await _relay.send(request);

    if (response.success) {
      final json = jsonDecode(response.bodyUtf8!);
      print('Login successful: $json');
    } else {
      print('Login failed: ${response.errorMessage}');
    }
  } on PlatformException catch (e) {
    print('Platform error: ${e.message}');
  } catch (error) {
    print('Unexpected error: $error');
  }
}
```

`RelayResponse` fields: `success`, `statusCode`, `headers` (`Map<String, List<String>>`),
`bodyUtf8`, `bodyBase64`, `errorMessage`, and `decodeBodyBase64ToUtf8()`.

### Streaming (SSE / long-lived responses)

```dart
final sub = _relay
    .stream(RelayRequest(
      serverUrl: 'https://your-relay-server.com',
      route: '/api/events',
      method: 'GET',
    ))
    .listen((event) {
      switch (event) {
        case RelayResponseStart():
          // status + headers available
          break;
        case RelayResponseChunk():
          // raw decrypted bytes — parse text/event-stream yourself if needed
          break;
      }
    });
// Cancel to stop the stream: await sub.cancel();
```

> The transport delivers **raw decrypted bytes** and does not parse `text/event-stream` —
> feed chunks to the same line parser you already use for a direct HTTP SSE response.

### File Upload (chunked)

For large uploads, start with `startUpload(...)` on `MteRelayClient` and write the body through
`MteRelayClientPlugin`'s chunk stream (`sendChunk`/`closeStream`); the native
library requests the body one chunk at a time and encrypts each chunk as it is written, so
the file is never fully loaded into memory. See the GitHub README for the full pattern.

## API Reference

See the [complete README](https://github.com/Eclypses/relay-client-plugin-flutter/blob/main/README.md) for full API details. Key types:

- **`MteRelayClient`** (primary):
  - `initialize()` — validate license; pair lazily on first request
  - `send(RelayRequest)` → `RelayResponse` — buffered request/response
  - `stream(RelayRequest)` → `Stream<RelayResponseEvent>` — `RelayResponseStart` / `RelayResponseChunk`
  - `startUpload(...)` / `startDownload(...)` / `cancelOperation(id)` / `repair(serverUrl)`
  - `events` — `Stream<RelayOperationEvent>` (observability only)
- **`RelayHttpClient`** — a thin `http.Client` over `stream()` (drop-in for `package:http`)
- **`RelayRequest`** — `serverUrl`, `route`, `method`, `headers`, `unencryptedHeaders`, `body` (`Uint8List`), `pathnamePrefix`; `RelayRequest.text(body: '…')` for a string body. `bodyUtf8` is on the *response*, not the request
- **`RelayResponse`** — `success`, `statusCode`, `headers`, `bodyUtf8`, `bodyBase64`, `errorMessage`
- **`MteRelayClientPlugin`** — chunk-based streaming uploads

## Support

**Email:** [info@eclypses.com](mailto:info@eclypses.com)  
**Web:** [www.eclypses.com](https://www.eclypses.com)

## Additional Resources

- [GitHub Repository](https://github.com/Eclypses/relay-client-plugin-flutter) – Source code and comprehensive examples
- [Release Notes](https://github.com/Eclypses/relay-client-plugin-flutter/releases) – Latest updates and changes

---

**All trademarks of Eclypses Inc.** may not be used without Eclypses Inc.'s prior written consent.
