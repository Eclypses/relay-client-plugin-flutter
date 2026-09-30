import 'dart:convert';
import 'dart:typed_data';

/// One event in a relay response stream, mirroring the native libs' streaming core
/// (iOS `RelayResponseEvent`). Every response — an ordinary buffered reply or a
/// long-lived event stream — arrives as a single [RelayResponseStart] (once the
/// status and headers are known) followed by zero or more [RelayResponseChunk]s as
/// decrypted body bytes arrive. Normal completion is the stream finishing; failure
/// is a stream error (a typed [RelayException] for relay-layer failures).
sealed class RelayResponseEvent {}

/// The response status and headers, emitted once before any body chunk.
final class RelayResponseStart extends RelayResponseEvent {
  RelayResponseStart({required this.statusCode, required this.headers});

  final int statusCode;
  final Map<String, List<String>> headers;
}

/// A decrypted segment of the response body. Fires 0..N times.
final class RelayResponseChunk extends RelayResponseEvent {
  RelayResponseChunk(this.bytes);

  final Uint8List bytes;
}

class RelayClientSettings {
  RelayClientSettings({
    required this.minPairs,
    required this.basePairs,
    required this.maxPairs,
    required this.keepAliveIntervalSeconds,
    required this.acquisitionWaitTime,
  });

  final int minPairs;
  final int basePairs;
  final int maxPairs;
  final int keepAliveIntervalSeconds;
  final double acquisitionWaitTime;

  void validate() {
    if (keepAliveIntervalSeconds < 60 || keepAliveIntervalSeconds > 600) {
      throw ArgumentError(
        'keepAliveIntervalSeconds must be between 60 and 600.',
      );
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'minPairs': minPairs,
      'basePairs': basePairs,
      'maxPairs': maxPairs,
      'keepAliveIntervalSeconds': keepAliveIntervalSeconds,
      'acquisitionWaitTime': acquisitionWaitTime,
    };
  }

  factory RelayClientSettings.fromMap(Map<dynamic, dynamic> map) {
    return RelayClientSettings(
      minPairs: map['minPairs'] as int? ?? 0,
      basePairs: map['basePairs'] as int? ?? 0,
      maxPairs: map['maxPairs'] as int? ?? 0,
      keepAliveIntervalSeconds: map['keepAliveIntervalSeconds'] as int? ?? 300,
      acquisitionWaitTime:
          (map['acquisitionWaitTime'] as num? ?? 0).toDouble(),
    );
  }
}

class RelayRequest {
  RelayRequest({
    required this.serverUrl,
    required this.method,
    required this.route,
    this.pathnamePrefix,
    this.headers = const {},
    this.unencryptedHeaders = const [],
    this.body,
    this.contentType,
    this.requestId,
  });

  /// Convenience for a UTF-8 text body (e.g. a JSON string).
  factory RelayRequest.text({
    required String serverUrl,
    required String method,
    required String route,
    String? pathnamePrefix,
    Map<String, String> headers = const {},
    List<String> unencryptedHeaders = const [],
    required String body,
    String? contentType,
    String? requestId,
  }) {
    return RelayRequest(
      serverUrl: serverUrl,
      method: method,
      route: route,
      pathnamePrefix: pathnamePrefix,
      headers: headers,
      unencryptedHeaders: unencryptedHeaders,
      body: Uint8List.fromList(utf8.encode(body)),
      contentType: contentType,
      requestId: requestId,
    );
  }

  final String serverUrl;
  final String method;
  final String route;
  final String? pathnamePrefix;
  final Map<String, String> headers;
  /// Header names to leave **unencrypted** on the hop to the relay, so
  /// infrastructure between the app and the relay can read them. Everything
  /// else is encrypted, and the empty default encrypts everything.
  ///
  /// This was `headersToEncrypt` and meant the opposite. Porting a list across
  /// the rename unchanged exposes exactly the headers it used to protect — in
  /// most cases the correct migration is to drop the argument. Reserved names
  /// (`Content-Type`, `Content-Length`, `Host`, `X-MTE-Relay-Route`) are always
  /// encrypted and throw if listed.
  final List<String> unencryptedHeaders;

  /// The request body as raw bytes — the primitive. Use [RelayRequest.text] for
  /// a UTF-8 string body.
  final Uint8List? body;
  final String? contentType;
  final String? requestId;

  Map<String, dynamic> toMap() {
    return {
      'serverUrl': serverUrl,
      'method': method,
      'route': route,
      'pathnamePrefix': pathnamePrefix,
      'headers': headers,
      'unencryptedHeaders': unencryptedHeaders,
      'body': body,
      'contentType': contentType,
      'requestId': requestId,
    };
  }
}

class RelayFileUploadRequest {
  RelayFileUploadRequest({
    required this.serverUrl,
    required this.route,
    this.pathnamePrefix,
    this.headers = const {},
    this.unencryptedHeaders = const [],
    this.contentType,
    this.fileName,
    this.requestId,
  });

  final String serverUrl;
  final String route;
  final String? pathnamePrefix;
  final Map<String, String> headers;
  /// Header names to leave **unencrypted** on the hop to the relay, so
  /// infrastructure between the app and the relay can read them. Everything
  /// else is encrypted, and the empty default encrypts everything.
  ///
  /// This was `headersToEncrypt` and meant the opposite. Porting a list across
  /// the rename unchanged exposes exactly the headers it used to protect — in
  /// most cases the correct migration is to drop the argument. Reserved names
  /// (`Content-Type`, `Content-Length`, `Host`, `X-MTE-Relay-Route`) are always
  /// encrypted and throw if listed.
  final List<String> unencryptedHeaders;
  final String? contentType;
  final String? fileName;
  final String? requestId;

  Map<String, dynamic> toMap() {
    return {
      'serverUrl': serverUrl,
      'route': route,
      // Both native handlers require it, and Android accepts only POST for a streamed
      // upload. Not a field: there is no other method to choose.
      'method': 'POST',
      'pathnamePrefix': pathnamePrefix,
      'headers': headers,
      'unencryptedHeaders': unencryptedHeaders,
      'contentType': contentType,
      'fileName': fileName,
      'requestId': requestId,
    };
  }
}

class RelayFileDownloadRequest {
  RelayFileDownloadRequest({
    required this.serverUrl,
    required this.route,
    required this.destinationPath,
    this.pathnamePrefix,
    this.headers = const {},
    this.unencryptedHeaders = const [],
    this.requestId,
  });

  final String serverUrl;
  final String route;
  final String destinationPath;
  final String? pathnamePrefix;
  final Map<String, String> headers;
  /// Header names to leave **unencrypted** on the hop to the relay, so
  /// infrastructure between the app and the relay can read them. Everything
  /// else is encrypted, and the empty default encrypts everything.
  ///
  /// This was `headersToEncrypt` and meant the opposite. Porting a list across
  /// the rename unchanged exposes exactly the headers it used to protect — in
  /// most cases the correct migration is to drop the argument. Reserved names
  /// (`Content-Type`, `Content-Length`, `Host`, `X-MTE-Relay-Route`) are always
  /// encrypted and throw if listed.
  final List<String> unencryptedHeaders;
  final String? requestId;

  Map<String, dynamic> toMap() {
    return {
      'serverUrl': serverUrl,
      'route': route,
      // Both native handlers require it, and Android accepts only GET for a streamed
      // download. Not a field: there is no other method to choose.
      'method': 'GET',
      'destinationPath': destinationPath,
      'pathnamePrefix': pathnamePrefix,
      'headers': headers,
      'unencryptedHeaders': unencryptedHeaders,
      'requestId': requestId,
    };
  }
}

class RelayResponse {
  RelayResponse({
    required this.success,
    required this.statusCode,
    required this.headers,
    this.bodyUtf8,
    this.bodyBase64,
    this.errorMessage,
    this.requestId,
  });

  final bool success;
  final int statusCode;
  final Map<String, List<String>> headers;
  final String? bodyUtf8;
  final String? bodyBase64;
  final String? errorMessage;
  final String? requestId;

  Map<String, dynamic> toMap() {
    return {
      'success': success,
      'statusCode': statusCode,
      'headers': headers,
      'bodyUtf8': bodyUtf8,
      'bodyBase64': bodyBase64,
      'errorMessage': errorMessage,
      'requestId': requestId,
    };
  }

  factory RelayResponse.fromMap(Map<dynamic, dynamic> map) {
    // Native iOS/Android returns response body under 'data' (Uint8List).
    // Dart-originated maps use 'bodyUtf8' / 'bodyBase64'.
    String? bodyUtf8 = map['bodyUtf8'] as String?;
    String? bodyBase64 = map['bodyBase64'] as String?;
    if (bodyUtf8 == null && bodyBase64 == null) {
      final raw = map['data'];
      if (raw is List<int> && raw.isNotEmpty) {
        bodyUtf8 = utf8.decode(raw, allowMalformed: true);
      } else if (raw is String && raw.isNotEmpty) {
        bodyUtf8 = raw;
      }
    }

    return RelayResponse(
      success: map['success'] as bool? ?? false,
      statusCode: map['statusCode'] as int? ?? 0,
      headers: _toStringListMap(map['headers']),
      bodyUtf8: bodyUtf8,
      bodyBase64: bodyBase64,
      // Native uses 'error' key; Dart-originated maps use 'errorMessage'.
      errorMessage: map['errorMessage'] as String? ?? map['error'] as String?,
      requestId: map['requestId'] as String?,
    );
  }

  String? decodeBodyBase64ToUtf8() {
    if (bodyBase64 == null) {
      return null;
    }
    return utf8.decode(base64Decode(bodyBase64!));
  }
}

enum RelayOperationEventType {
  uploadProgress,
  uploadCompleted,
  uploadError,
  downloadProgress,
  downloadCompleted,
  downloadError,
  sseOpened,
  sseData,
  sseCompleted,
  sseCancelled,
  sseError,
  connecting,
  response,
  firstVisibleText,
  event,
  malformedRecord,
  completed,
  cancelled,
  failed,
  unknown,
}

RelayOperationEventType relayOperationEventTypeFromWire(String? value) {
  switch (value) {
    case 'uploadProgress':
      return RelayOperationEventType.uploadProgress;
    case 'uploadCompleted':
      return RelayOperationEventType.uploadCompleted;
    case 'uploadError':
      return RelayOperationEventType.uploadError;
    case 'downloadProgress':
      return RelayOperationEventType.downloadProgress;
    case 'downloadCompleted':
      return RelayOperationEventType.downloadCompleted;
    case 'downloadError':
      return RelayOperationEventType.downloadError;
    case 'sseOpened':
      return RelayOperationEventType.sseOpened;
    case 'sseData':
      return RelayOperationEventType.sseData;
    case 'sseCompleted':
      return RelayOperationEventType.sseCompleted;
    case 'sseCancelled':
      return RelayOperationEventType.sseCancelled;
    case 'sseError':
      return RelayOperationEventType.sseError;
    case 'connecting':
      return RelayOperationEventType.connecting;
    case 'response':
      return RelayOperationEventType.response;
    case 'firstVisibleText':
      return RelayOperationEventType.firstVisibleText;
    case 'event':
      return RelayOperationEventType.event;
    case 'malformedRecord':
      return RelayOperationEventType.malformedRecord;
    case 'completed':
      return RelayOperationEventType.completed;
    case 'cancelled':
      return RelayOperationEventType.cancelled;
    case 'failed':
      return RelayOperationEventType.failed;
    default:
      return RelayOperationEventType.unknown;
  }
}

class RelayOperationEvent {
  RelayOperationEvent({
    required this.type,
    this.operationId,
    this.streamId,
    this.statusCode,
    this.headers = const {},
    this.bytesCompleted,
    this.totalBytes,
    this.dataBase64,
    this.message,
    this.timestamp,
    this.rawRecord,
    this.requestId,
  });

  final RelayOperationEventType type;
  final String? operationId;
  final String? streamId;
  final int? statusCode;
  final Map<String, List<String>> headers;
  final int? bytesCompleted;
  final int? totalBytes;
  final String? dataBase64;
  final String? message;
  final DateTime? timestamp;
  final String? rawRecord;
  final String? requestId;

  factory RelayOperationEvent.fromMap(Map<dynamic, dynamic> map) {
    return RelayOperationEvent(
      type: relayOperationEventTypeFromWire(map['type'] as String?),
      operationId: map['operationId'] as String?,
      streamId: map['streamId'] as String?,
      statusCode: map['statusCode'] as int?,
      headers: _toStringListMap(map['headers']),
      bytesCompleted: map['bytesCompleted'] as int?,
      totalBytes: map['totalBytes'] as int?,
      dataBase64: map['dataBase64'] as String?,
      message: map['message'] as String?,
      timestamp: _parseTimestamp(map['timestamp']),
      rawRecord: map['rawRecord'] as String?,
      requestId: map['requestId'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'operationId': operationId,
      'streamId': streamId,
      'statusCode': statusCode,
      'headers': headers,
      'bytesCompleted': bytesCompleted,
      'totalBytes': totalBytes,
      'dataBase64': dataBase64,
      'message': message,
      'timestamp': timestamp?.toIso8601String(),
      'rawRecord': rawRecord,
      'requestId': requestId,
    };
  }
}

class RelayKeepAliveDiagnostics {
  RelayKeepAliveDiagnostics({
    required this.serverUrl,
    required this.raw,
  });

  final String serverUrl;
  final String raw;
}

Map<String, List<String>> _toStringListMap(dynamic source) {
  if (source is! Map) {
    return const {};
  }

  final parsed = <String, List<String>>{};
  source.forEach((dynamic k, dynamic v) {
    if (k == null) {
      return;
    }

    if (v is List) {
      parsed[k.toString()] = v.whereType<Object>().map((e) => e.toString()).toList();
      return;
    }

    if (v == null) {
      parsed[k.toString()] = const [];
      return;
    }

    parsed[k.toString()] = <String>[v.toString()];
  });
  return parsed;
}

DateTime? _parseTimestamp(dynamic value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}