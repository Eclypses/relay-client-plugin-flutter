import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'mte_relay_platform_interface.dart';
import 'relay_exceptions.dart';
import 'relay_models.dart';

class MteRelayClient {
  Future<void> initialize() {
    return MteRelayClientPluginPlatform.instance.initialize();
  }

  /// The per-call streaming primitive. Sends [request] through the relay and
  /// emits its response as it arrives: a single [RelayResponseStart] once the
  /// status and headers are known, then a [RelayResponseChunk] for each decrypted
  /// body segment. A server-sent-event endpoint is simply a response whose stream
  /// stays open. Normal completion ends the stream; a relay-layer failure is a
  /// typed [RelayException] stream error.
  ///
  /// This is the one place the shared native event bus is demultiplexed into a
  /// per-call stream — callers get their own stream, never the global bus.
  Stream<RelayResponseEvent> stream(RelayRequest request) {
    final platform = MteRelayClientPluginPlatform.instance;
    final controller = StreamController<RelayResponseEvent>();
    // Events for this request arrive on the shared bus tagged with a streamId we
    // only learn once startStream returns. Subscribe first and hold anything
    // that lands in that gap, then replay it once the id is known.
    //
    // Only events carrying this stream's id belong to it. The bus also carries
    // untagged events (repair and settings results), and treating one of those
    // as ours ended every open request when a repair finished.
    String? streamId;
    final pending = <RelayOperationEvent>[];
    late final StreamSubscription<RelayOperationEvent> subscription;

    void finish() {
      subscription.cancel();
      if (!controller.isClosed) controller.close();
    }

    void handle(RelayOperationEvent event) {
      switch (event.type) {
        case RelayOperationEventType.sseOpened:
          controller.add(RelayResponseStart(
            statusCode: event.statusCode ?? 200,
            headers: event.headers,
          ));
        case RelayOperationEventType.sseData:
          final data = event.dataBase64;
          if (data != null && data.isNotEmpty) {
            controller.add(RelayResponseChunk(base64Decode(data)));
          }
        case RelayOperationEventType.sseCompleted:
        case RelayOperationEventType.completed:
          finish();
        case RelayOperationEventType.sseCancelled:
        // ignore: deprecated_member_use_from_same_package
        case RelayOperationEventType.cancelled:
          if (!controller.isClosed) {
            controller.addError(
              RelayException(message: 'Relay request was cancelled'),
            );
          }
          finish();
        case RelayOperationEventType.sseError:
        case RelayOperationEventType.failed:
          if (!controller.isClosed) controller.addError(_streamError(event));
          finish();
        default:
          break;
      }
    }

    subscription = platform.events.listen((event) {
      if (streamId == null) {
        pending.add(event);
        return;
      }
      if (event.streamId == streamId) handle(event);
    });

    controller.onCancel = () {
      final id = streamId;
      if (id != null) unawaited(platform.cancelStream(id));
      subscription.cancel();
    };

    platform.startStream(request).then((id) {
      streamId = id;
      for (final event in pending) {
        if (event.streamId == streamId) handle(event);
      }
      pending.clear();
    }).catchError((Object error) {
      if (!controller.isClosed) controller.addError(_startError(error));
      finish();
    });

    return controller.stream;
  }

  /// Buffered convenience over [stream]: accumulates every chunk and resolves once
  /// the response completes. A single-shot reply is just a stream that finishes
  /// quickly. A stream that ends without a status is a [RelayException], never a
  /// response with status 0.
  Future<RelayResponse> send(RelayRequest request) async {
    RelayResponseStart? start;
    final body = BytesBuilder(copy: false);
    await for (final event in stream(request)) {
      switch (event) {
        case RelayResponseStart():
          start = event;
        case RelayResponseChunk():
          body.add(event.bytes);
      }
    }
    if (start == null) {
      throw RelayException(message: 'Relay stream ended before any response');
    }
    final status = start.statusCode;
    return RelayResponse(
      success: status >= 200 && status < 300,
      statusCode: status,
      headers: start.headers,
      bodyBase64: base64Encode(body.takeBytes()),
      requestId: request.requestId,
    );
  }

  RelayException _streamError(RelayOperationEvent event) {
    final status = event.statusCode ?? -1;
    final message = event.message ?? 'Relay request failed';
    final reason = event.reason ?? _relayErrorReason(event.headers, status);
    if (reason != null || event.outcome != null) {
      return mapRelayProtocolException(
        statusCode: status,
        message: message,
        rawMessage: event.message,
        reason: reason,
        outcome: event.outcome,
      );
    }
    // Not a relay refusal: a proxy's 413, a network failure, a request refused before
    // sending. The status says what it can; there is no reason to report.
    return RelayException(message: message, statusCode: status);
  }

  /// A request the platform refused to start. iOS reports a relay refusal met before the
  /// response opened this way, with the relay's code in `details`; it arrives as the same
  /// typed exception a stream error would, so `on RelayException` works on both platforms.
  Object _startError(Object error) {
    if (error is! PlatformException) return error;
    final details = error.details;
    return _streamError(RelayOperationEvent(
      type: RelayOperationEventType.sseError,
      statusCode: details is Map ? details['statusCode'] as int? : null,
      reason: details is Map ? details['reason'] as String? : null,
      outcome: details is Map ? details['outcome'] as String? : null,
      message: error.message,
    ));
  }

  /// The reason from `X-MTE-Relay-Error: <code> <reason>`, which Android forwards in the
  /// event's headers. Only trusted when its code matches the status.
  String? _relayErrorReason(Map<String, List<String>> headers, int status) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() != 'x-mte-relay-error' || entry.value.isEmpty) continue;
      final parts = entry.value.first.trim().split(' ');
      if (parts.length >= 2 && int.tryParse(parts[0]) == status) return parts[1];
    }
    return null;
  }

  /// Starts a streamed upload. **You supply the body.**
  ///
  /// The relay never reads a file from disk. This call opens the upload and the
  /// native side answers with a stream id on [MteRelayClientPlugin.getFileStream];
  /// write the bytes with `sendChunk`, then `closeStream`. Nothing is sent until
  /// you do, so an upload that is started and never pumped simply waits.
  ///
  /// The bytes are encrypted and forwarded as they arrive, so the file is never
  /// held in memory. The relay still counts the whole body against its
  /// `maxRequestBodyBytes`: an upload whose `Content-Length` is over it is
  /// refused before anything is sent.
  ///
  /// Returns the operation id as soon as the upload starts; pass it to
  /// [cancelOperation] to stop it. The outcome arrives as a `response` (or
  /// `failed`) event on [events], and on the plugin's
  /// `relayStreamResponseStream`.
  Future<String> startUpload(RelayFileUploadRequest request) {
    return MteRelayClientPluginPlatform.instance.startUpload(request);
  }

  /// Starts a streamed download. **You supply the destination.**
  ///
  /// [RelayFileDownloadRequest.destinationPath] is required and must be a
  /// writable path your app owns; the decrypted bytes are written straight there
  /// and never held in memory. Choosing that location is deliberately the app's
  /// job — the plugin has no business picking a directory on your behalf.
  ///
  /// Returns the operation id as soon as the download starts; pass it to
  /// [cancelOperation] to stop it. The outcome arrives as a `response` (or
  /// `failed`) event on [events]. No progress is reported: a relay response
  /// declares no length.
  Future<String> startDownload(RelayFileDownloadRequest request) {
    return MteRelayClientPluginPlatform.instance.startDownload(request);
  }

  /// Stops the upload, download or stream with [operationId], freeing its
  /// pair. Returns false when no operation has that id.
  Future<bool> cancelOperation(String operationId) {
    return MteRelayClientPluginPlatform.instance.cancelOperation(operationId);
  }

  Future<void> repair(String serverUrl, {String? pathnamePrefix}) {
    return MteRelayClientPluginPlatform.instance.repair(
      serverUrl,
      pathnamePrefix: pathnamePrefix,
    );
  }

  Future<RelayClientSettings> getSettings({
    required String serverUrl,
    String? pathnamePrefix,
  }) {
    return MteRelayClientPluginPlatform.instance.getSettings(
      serverUrl: serverUrl,
      pathnamePrefix: pathnamePrefix,
    );
  }

  Future<String> updateSettings(
    String serverUrl,
    RelayClientSettings settings, {
    String? pathnamePrefix,
  }) {
    return MteRelayClientPluginPlatform.instance.updateSettings(
      serverUrl,
      settings,
      pathnamePrefix: pathnamePrefix,
    );
  }

  Future<RelayKeepAliveDiagnostics> getKeepAliveDiagnostics(String serverUrl) {
    return MteRelayClientPluginPlatform.instance
        .getKeepAliveDiagnostics(serverUrl);
  }

  Future<void> enableFileLogging(bool enabled) {
    return MteRelayClientPluginPlatform.instance.enableRelayFileLogging(enabled);
  }

  Future<String> readLogFile() {
    return MteRelayClientPluginPlatform.instance.readRelayLogFile();
  }

  Future<void> clearLogFile() {
    return MteRelayClientPluginPlatform.instance.clearRelayLogFile();
  }

  Stream<RelayOperationEvent> get events =>
      MteRelayClientPluginPlatform.instance.events;
}