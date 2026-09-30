import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mte_relay/relay_models.dart';

void main() {
  group('RelayClientSettings', () {
    test('toMap / fromMap round trip', () {
      final settings = RelayClientSettings(
        minPairs: 2,
        basePairs: 4,
        maxPairs: 8,
        keepAliveIntervalSeconds: 300,
        acquisitionWaitTime: 1.5,
      );
      final back = RelayClientSettings.fromMap(settings.toMap());
      expect(back.minPairs, 2);
      expect(back.basePairs, 4);
      expect(back.maxPairs, 8);
      expect(back.keepAliveIntervalSeconds, 300);
      expect(back.acquisitionWaitTime, 1.5);
    });

    test('fromMap applies defaults for missing keys', () {
      final settings = RelayClientSettings.fromMap(<dynamic, dynamic>{});
      expect(settings.minPairs, 0);
      expect(settings.keepAliveIntervalSeconds, 300);
      expect(settings.acquisitionWaitTime, 0);
    });

    test('validate rejects out-of-range keepAlive and accepts in-range', () {
      RelayClientSettings base({required int keepAlive}) => RelayClientSettings(
            minPairs: 1,
            basePairs: 1,
            maxPairs: 1,
            keepAliveIntervalSeconds: keepAlive,
            acquisitionWaitTime: 0,
          );
      expect(() => base(keepAlive: 30).validate(), throwsArgumentError);
      expect(() => base(keepAlive: 601).validate(), throwsArgumentError);
      base(keepAlive: 300).validate(); // no throw
    });
  });

  group('RelayRequest', () {
    test('toMap carries all fields', () {
      final map = RelayRequest(
        serverUrl: 'https://x',
        method: 'POST',
        route: '/a',
        pathnamePrefix: '/p',
        headers: {'h': 'v'},
        unencryptedHeaders: ['h'],
        body: Uint8List.fromList([1, 2, 3]),
        contentType: 'application/json',
        requestId: 'id1',
      ).toMap();
      expect(map['serverUrl'], 'https://x');
      expect(map['method'], 'POST');
      expect(map['route'], '/a');
      expect(map['pathnamePrefix'], '/p');
      expect(map['headers'], {'h': 'v'});
      expect(map['unencryptedHeaders'], ['h']);
      expect(map['body'], Uint8List.fromList([1, 2, 3]));
      expect(map['contentType'], 'application/json');
      expect(map['requestId'], 'id1');
    });

    test('text factory UTF-8-encodes the body', () {
      final request = RelayRequest.text(
        serverUrl: 'https://x',
        method: 'POST',
        route: '/a',
        body: '{"k":"v"}',
      );
      expect(request.body, Uint8List.fromList(utf8.encode('{"k":"v"}')));
      expect(request.method, 'POST');
    });
  });

  // The native handlers reject a call missing any of these with INVALID_ARGUMENTS, and the
  // fake-platform tests elsewhere cannot see that. `method` was dropped once, when the
  // duplicate upload APIs were collapsed, and every upload and download failed on both
  // platforms. These lists mirror the guards in MteRelayClientPlugin.swift and .java.
  group('Method-channel contract with the native handlers', () {
    test('an upload sends every argument the native handlers require', () {
      final args = RelayFileUploadRequest(serverUrl: 'https://relay.example', route: '/upload')
          .toMap();
      for (final key in ['serverUrl', 'route', 'method', 'headers', 'unencryptedHeaders']) {
        expect(args[key], isNotNull, reason: key);
      }
      expect(args['method'], 'POST', reason: 'Android accepts only POST for an upload');
    });

    test('a download sends every argument the native handlers require', () {
      final args = RelayFileDownloadRequest(
        serverUrl: 'https://relay.example',
        route: '/file',
        destinationPath: '/tmp/file',
      ).toMap();
      for (final key in [
        'serverUrl', 'route', 'method', 'headers', 'unencryptedHeaders', 'destinationPath'
      ]) {
        expect(args[key], isNotNull, reason: key);
      }
      expect(args['method'], 'GET', reason: 'Android accepts only GET for a download');
    });
  });

  group('File request models', () {
    test('RelayFileUploadRequest.toMap', () {
      final map = RelayFileUploadRequest(
        serverUrl: 'https://x',
        route: '/u',
        headers: {'a': 'b'},
        unencryptedHeaders: ['a'],
        contentType: 'text/plain',
        fileName: 'f.txt',
        requestId: 'u1',
      ).toMap();
      expect(map['fileName'], 'f.txt');
      expect(map['contentType'], 'text/plain');
      expect(map['requestId'], 'u1');
    });

    test('RelayFileDownloadRequest.toMap', () {
      final map = RelayFileDownloadRequest(
        serverUrl: 'https://x',
        route: '/d',
        destinationPath: '/tmp/out',
        requestId: 'd1',
      ).toMap();
      expect(map['destinationPath'], '/tmp/out');
      expect(map['requestId'], 'd1');
    });
  });

  group('RelayResponse', () {
    test('toMap', () {
      final map = RelayResponse(
        success: true,
        statusCode: 200,
        headers: {
          'content-type': ['application/json'],
        },
        bodyUtf8: '{"ok":true}',
        requestId: 'r1',
      ).toMap();
      expect(map['success'], true);
      expect(map['statusCode'], 200);
      expect(map['bodyUtf8'], '{"ok":true}');
      expect(map['requestId'], 'r1');
    });

    test('fromMap with explicit bodyUtf8', () {
      final response = RelayResponse.fromMap({
        'success': true,
        'statusCode': 200,
        'headers': {
          'h': ['v'],
        },
        'bodyUtf8': 'hi',
      });
      expect(response.success, true);
      expect(response.bodyUtf8, 'hi');
      expect(response.headers['h'], ['v']);
    });

    test('fromMap decodes native byte data to UTF-8', () {
      final response = RelayResponse.fromMap({
        'success': true,
        'statusCode': 200,
        'data': utf8.encode('bytes-body'),
      });
      expect(response.bodyUtf8, 'bytes-body');
    });

    test('fromMap accepts data as a String', () {
      final response = RelayResponse.fromMap({
        'success': true,
        'statusCode': 200,
        'data': 'string-body',
      });
      expect(response.bodyUtf8, 'string-body');
    });

    test('fromMap maps the native error key to errorMessage', () {
      final response = RelayResponse.fromMap({
        'success': false,
        'statusCode': 500,
        'error': 'boom',
      });
      expect(response.errorMessage, 'boom');
    });

    test('decodeBodyBase64ToUtf8 decodes, and is null without base64', () {
      final withBody = RelayResponse(
        success: true,
        statusCode: 200,
        headers: const {},
        bodyBase64: base64Encode(utf8.encode('decoded')),
      );
      expect(withBody.decodeBodyBase64ToUtf8(), 'decoded');

      final withoutBody =
          RelayResponse(success: true, statusCode: 200, headers: const {});
      expect(withoutBody.decodeBodyBase64ToUtf8(), isNull);
    });

    test('fromMap coerces scalar/null/list header values', () {
      final response = RelayResponse.fromMap({
        'success': true,
        'statusCode': 200,
        'headers': {
          'a': 'scalar',
          'b': null,
          'c': ['x', 'y'],
        },
      });
      expect(response.headers['a'], ['scalar']);
      expect(response.headers['b'], <String>[]);
      expect(response.headers['c'], ['x', 'y']);
    });

    test('fromMap tolerates non-map headers', () {
      final response = RelayResponse.fromMap({
        'success': true,
        'statusCode': 200,
        'headers': 'not-a-map',
      });
      expect(response.headers, isEmpty);
    });
  });

  group('RelayResponseEvent', () {
    test('start and chunk carry their payloads and switch exhaustively', () {
      final start = RelayResponseStart(statusCode: 200, headers: {
        'h': ['v'],
      });
      expect(start.statusCode, 200);
      expect(start.headers['h'], ['v']);

      final chunk = RelayResponseChunk(Uint8List.fromList([1, 2, 3]));
      expect(chunk.bytes, [1, 2, 3]);

      String label(RelayResponseEvent e) => switch (e) {
            RelayResponseStart() => 'start',
            RelayResponseChunk() => 'chunk',
          };
      expect(label(start), 'start');
      expect(label(chunk), 'chunk');
    });
  });

  group('RelayOperationEvent', () {
    test('fromMap / toMap round trip', () {
      final event = RelayOperationEvent.fromMap({
        'type': 'sseData',
        'operationId': 'op',
        'streamId': 's',
        'statusCode': 200,
        'headers': {
          'h': ['v'],
        },
        'bytesCompleted': 10,
        'totalBytes': 20,
        'dataBase64': 'ZGF0YQ==',
        'message': 'm',
        'timestamp': '2026-07-24T12:00:00Z',
        'rawRecord': 'raw',
        'requestId': 'req',
      });
      expect(event.type, RelayOperationEventType.sseData);
      expect(event.operationId, 'op');
      expect(event.streamId, 's');
      expect(event.statusCode, 200);
      expect(event.bytesCompleted, 10);
      expect(event.totalBytes, 20);
      expect(event.dataBase64, 'ZGF0YQ==');
      expect(event.message, 'm');
      expect(event.timestamp, isNotNull);
      expect(event.rawRecord, 'raw');
      expect(event.requestId, 'req');

      final map = event.toMap();
      expect(map['type'], 'sseData');
      expect(map['timestamp'], '2026-07-24T12:00:00.000Z');
    });

    test('unknown type and absent timestamp', () {
      final event = RelayOperationEvent.fromMap({'type': 'not-a-type'});
      expect(event.type, RelayOperationEventType.unknown);
      expect(event.timestamp, isNull);
    });

    test('every wire type maps to its enum, and unknowns fall back', () {
      const pairs = <String, RelayOperationEventType>{
        'uploadProgress': RelayOperationEventType.uploadProgress,
        'uploadCompleted': RelayOperationEventType.uploadCompleted,
        'uploadError': RelayOperationEventType.uploadError,
        'downloadProgress': RelayOperationEventType.downloadProgress,
        'downloadCompleted': RelayOperationEventType.downloadCompleted,
        'downloadError': RelayOperationEventType.downloadError,
        'sseOpened': RelayOperationEventType.sseOpened,
        'sseData': RelayOperationEventType.sseData,
        'sseCompleted': RelayOperationEventType.sseCompleted,
        'sseCancelled': RelayOperationEventType.sseCancelled,
        'sseError': RelayOperationEventType.sseError,
        'connecting': RelayOperationEventType.connecting,
        'response': RelayOperationEventType.response,
        'firstVisibleText': RelayOperationEventType.firstVisibleText,
        'event': RelayOperationEventType.event,
        'malformedRecord': RelayOperationEventType.malformedRecord,
        'completed': RelayOperationEventType.completed,
        'cancelled': RelayOperationEventType.cancelled,
        'failed': RelayOperationEventType.failed,
      };
      pairs.forEach((wire, expected) {
        expect(relayOperationEventTypeFromWire(wire), expected, reason: wire);
      });
      expect(relayOperationEventTypeFromWire(null),
          RelayOperationEventType.unknown);
      expect(relayOperationEventTypeFromWire('bogus'),
          RelayOperationEventType.unknown);
    });
  });

  group('RelayKeepAliveDiagnostics', () {
    test('holds serverUrl and raw', () {
      final diagnostics =
          RelayKeepAliveDiagnostics(serverUrl: 'https://x', raw: 'healthy');
      expect(diagnostics.serverUrl, 'https://x');
      expect(diagnostics.raw, 'healthy');
    });
  });
}
