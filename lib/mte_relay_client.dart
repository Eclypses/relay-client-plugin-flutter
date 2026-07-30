import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'mte_relay_client_plugin_platform_interface.dart';
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
      if (event.streamId != null && event.streamId != streamId) return;
      handle(event);
    });

    controller.onCancel = () {
      final id = streamId;
      if (id != null) unawaited(platform.cancelStream(id));
      subscription.cancel();
    };

    platform.startStream(request).then((id) {
      streamId = id;
      for (final event in pending) {
        if (event.streamId == null || event.streamId == streamId) handle(event);
      }
      pending.clear();
    }).catchError((Object error) {
      if (!controller.isClosed) controller.addError(error);
      finish();
    });

    return controller.stream;
  }

  /// Buffered convenience over [stream]: accumulates every chunk and resolves once
  /// the response completes. A single-shot reply is just a stream that finishes
  /// quickly.
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
    final status = start?.statusCode ?? 0;
    return RelayResponse(
      success: status >= 200 && status < 300,
      statusCode: status,
      headers: start?.headers ?? const {},
      bodyBase64: base64Encode(body.takeBytes()),
      requestId: request.requestId,
    );
  }

  RelayException _streamError(RelayOperationEvent event) {
    final status = event.statusCode ?? -1;
    final message = event.message ?? 'Relay request failed';
    if (status >= 559 && status <= 569) {
      return mapRelayProtocolException(
        statusCode: status,
        message: message,
        rawMessage: event.message,
      );
    }
    return RelayException(message: message, statusCode: status);
  }

  Future<String> startUpload(RelayFileUploadRequest request) {
    return MteRelayClientPluginPlatform.instance.startUpload(request);
  }

  Future<String> startDownload(RelayFileDownloadRequest request) {
    return MteRelayClientPluginPlatform.instance.startDownload(request);
  }

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