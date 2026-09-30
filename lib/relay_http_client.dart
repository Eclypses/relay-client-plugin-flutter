import 'dart:async';

import 'package:http/http.dart' as http;

import 'mte_relay_client.dart';
import 'relay_exceptions.dart';
import 'relay_models.dart';

/// A drop-in [http.Client] that routes every request through the MTE Relay.
///
/// A customer swaps `http.Client()` for `RelayHttpClient()` and keeps using
/// `get` / `post` / `send` exactly as before — the request they were already
/// building goes out as single-use MicroTokens, and the response comes back the
/// way `http` already delivers it.
///
/// Everything is a stream. [send] returns a [http.StreamedResponse] whose
/// `stream` is the relay's decrypted response bytes as they arrive; a
/// server-sent-event endpoint is simply a response whose stream stays open. The
/// buffered forms fall out for free: `get`/`post`/`read`/`Response.fromStream`
/// consume that stream to completion. There is no separate buffered path and no
/// relay-specific API to learn.
///
/// This is a thin adapter over [MteRelayClient.stream] — that is where the relay
/// request actually runs and the response is demultiplexed into a per-call stream.
///
/// ```dart
/// final client = RelayHttpClient();
/// final res = await client.post(Uri.parse('$mrsUrl/api/login'), body: json);
/// // …or read incrementally, for an event stream:
/// final streamed = await client.send(request);
/// await for (final chunk in streamed.stream) { … }
/// ```
class RelayHttpClient extends http.BaseClient {
  RelayHttpClient({MteRelayClient? client, String? pathnamePrefix})
      : _client = client ?? MteRelayClient(),
        _pathnamePrefix = pathnamePrefix;

  final MteRelayClient _client;
  final String? _pathnamePrefix;

  /// Memoised so concurrent first requests share one initialization rather than
  /// racing to run it twice.
  Future<void>? _initialization;

  /// Initializes the underlying relay.
  ///
  /// Optional: the first request does this for you. Call it yourself only to pay
  /// the licence check and pairing cost up front, or to surface a setup failure
  /// at a point of your choosing rather than on the first request.
  Future<void> initialize() => _ensureInitialized();

  /// The drop-in promise is that swapping `http.Client()` for this type changes
  /// nothing else, and that only holds if the caller is not also required to
  /// remember a setup call. The native side rejects every operation until the
  /// relay exists, so the first request initializes it.
  Future<void> _ensureInitialized() {
    return _initialization ??= _client.initialize();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await _ensureInitialized();
    final bodyBytes = await request.finalize().toBytes();
    final relayRequest = RelayRequest(
      serverUrl: _origin(request.url),
      method: request.method,
      route: _route(request.url),
      pathnamePrefix: _pathnamePrefix,
      headers: Map<String, String>.of(request.headers),
      contentType: request.headers['content-type'],
      body: bodyBytes.isEmpty ? null : bodyBytes,
    );

    final body = StreamController<List<int>>();
    final response = Completer<http.StreamedResponse>();
    late final StreamSubscription<RelayResponseEvent> subscription;

    subscription = _client.stream(relayRequest).listen(
      (event) {
        switch (event) {
          case RelayResponseStart():
            if (!response.isCompleted) {
              response.complete(
                http.StreamedResponse(
                  body.stream,
                  event.statusCode,
                  headers: _flattenHeaders(event.headers),
                  request: request,
                ),
              );
            }
          case RelayResponseChunk():
            body.add(event.bytes);
        }
      },
      onError: (Object error) {
        // As an http.Client, surface failures as http.ClientException so a
        // caller's existing `catch (ClientException)` still works. The typed,
        // retryable relay errors (pairingDesync, etc.) live one layer down, on
        // MteRelayClient.stream()/send(). Before the response opens, a failure is
        // the send() error; once opened, it is a body-stream error mid-flight.
        final clientError = _asClientException(error, request.url);
        if (!response.isCompleted) {
          response.completeError(clientError);
        } else if (!body.isClosed) {
          body.addError(clientError);
        }
      },
      onDone: () {
        if (!response.isCompleted) {
          response.completeError(
            http.ClientException('Relay stream closed before any response', request.url),
          );
        }
        if (!body.isClosed) body.close();
      },
      cancelOnError: false,
    );

    // Abandoning the response body tears down the relay stream.
    body.onCancel = subscription.cancel;

    return response.future;
  }

  /// `scheme://host[:port]`, dropping the port when it is the scheme default —
  /// the relay treats this as the origin and appends [_route] to it.
  String _origin(Uri url) {
    final defaultPort = url.scheme == 'https' ? 443 : 80;
    if (url.port == defaultPort || url.port == 0) {
      return '${url.scheme}://${url.host}';
    }
    return '${url.scheme}://${url.host}:${url.port}';
  }

  String _route(Uri url) {
    final path = url.path.isEmpty ? '/' : url.path;
    return url.hasQuery ? '$path?${url.query}' : path;
  }

  Map<String, String> _flattenHeaders(Map<String, List<String>> headers) {
    return headers.map((key, values) => MapEntry(key, values.join(', ')));
  }

  http.ClientException _asClientException(Object error, Uri url) {
    if (error is http.ClientException) return error;
    final message = error is RelayException ? error.message : error.toString();
    return http.ClientException(message, url);
  }
}
