import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mte_relay/mte_relay_client.dart';
import 'package:mte_relay/mte_relay_platform_interface.dart';
import 'package:mte_relay/relay_exceptions.dart';
import 'package:mte_relay/relay_models.dart';

import 'helpers/fake_mte_relay_client_plugin_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MteRelayClient', () {
    late MteRelayClientPluginPlatform originalPlatform;
    late FakeMteRelayClientPluginPlatform fakePlatform;
    late MteRelayClient client;

    setUp(() {
      originalPlatform = MteRelayClientPluginPlatform.instance;
      fakePlatform = FakeMteRelayClientPluginPlatform();
      MteRelayClientPluginPlatform.instance = fakePlatform;
      client = MteRelayClient();
    });

    tearDown(() async {
      MteRelayClientPluginPlatform.instance = originalPlatform;
      await fakePlatform.dispose();
    });

    test('initialize delegates to platform', () async {
      await client.initialize();
      expect(fakePlatform.initializeCallCount, 1);
    });

    // Drives the streaming path the way the native side does: startStream
    // returns a streamId, then events for that id land on the shared bus.
    void driveStream(List<RelayOperationEvent> events) {
      Future<void>.delayed(Duration.zero, () {
        for (final event in events) {
          fakePlatform.simulateEvent(event);
        }
      });
    }

    RelayOperationEvent opened(int status) => RelayOperationEvent(
          type: RelayOperationEventType.sseOpened,
          streamId: fakePlatform.startStreamResult,
          statusCode: status,
        );
    RelayOperationEvent data(String text) => RelayOperationEvent(
          type: RelayOperationEventType.sseData,
          streamId: fakePlatform.startStreamResult,
          dataBase64: base64Encode(utf8.encode(text)),
        );
    RelayOperationEvent completed() => RelayOperationEvent(
          type: RelayOperationEventType.sseCompleted,
          streamId: fakePlatform.startStreamResult,
        );

    test('send runs the request through stream() and folds it into a RelayResponse',
        () async {
      final future = client.send(RelayRequest.text(
        serverUrl: 'https://relay.example.com',
        method: 'POST',
        route: '/v1/data',
        body: '{"hello":"world"}',
      ));
      driveStream([opened(200), data('{"ok":'), data('true}'), completed()]);

      final response = await future;

      expect(fakePlatform.startStreamCallCount, 1);
      expect(fakePlatform.lastStartStreamRequest?.route, '/v1/data');
      expect(response.success, isTrue);
      expect(response.statusCode, 200);
      expect(response.decodeBodyBase64ToUtf8(), '{"ok":true}');
    });

    test('stream() emits a start then chunks, per call', () async {
      final events = <RelayResponseEvent>[];
      final done = client.stream(RelayRequest(
        serverUrl: 'https://relay.example.com',
        method: 'GET',
        route: '/events',
      )).forEach(events.add);
      driveStream([opened(200), data('a'), data('b'), completed()]);
      await done;

      expect(events.first, isA<RelayResponseStart>());
      expect((events.first as RelayResponseStart).statusCode, 200);
      final chunks = events.whereType<RelayResponseChunk>().toList();
      expect(chunks.map((c) => utf8.decode(c.bytes)), ['a', 'b']);
    });

    test('stream() surfaces a relay repair status as a typed exception', () async {
      final stream = client.stream(RelayRequest(
        serverUrl: 'https://relay.example.com',
        method: 'GET',
        route: '/x',
      ));
      driveStream([
        RelayOperationEvent(
          type: RelayOperationEventType.sseError,
          streamId: fakePlatform.startStreamResult,
          statusCode: 559,
          message: 'pair desynced',
        ),
      ]);

      await expectLater(
        stream.drain<void>(),
        throwsA(isA<PairReplacedRetryableException>()),
      );
    });

    test('startUpload/startDownload delegate and return operation ids', () async {
      final uploadId = await client.startUpload(
        RelayFileUploadRequest(
          serverUrl: 'https://relay.example.com',
          route: '/upload',
        ),
      );
      final downloadId = await client.startDownload(
        RelayFileDownloadRequest(
          serverUrl: 'https://relay.example.com',
          route: '/download',
          destinationPath: '/tmp/out.bin',
        ),
      );

      expect(fakePlatform.startUploadCallCount, 1);
      expect(fakePlatform.startDownloadCallCount, 1);
      expect(uploadId, fakePlatform.startUploadResult);
      expect(downloadId, fakePlatform.startDownloadResult);
    });

    test('cancelOperation delegates to platform', () async {
      final cancelled = await client.cancelOperation('op-1');
      expect(cancelled, isTrue);
      expect(fakePlatform.cancelOperationCallCount, 1);
    });

    test('cancelling a stream subscription cancels the relay stream', () async {
      final subscription = client.stream(RelayRequest(
        serverUrl: 'https://relay.example.com',
        method: 'GET',
        route: '/sse/counter',
      )).listen((_) {});
      driveStream([opened(200), data('one')]); // never completes on its own
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(fakePlatform.startStreamCallCount, 1);
      expect(fakePlatform.cancelStreamCallCount, 1);
    });

    test('settings and diagnostics delegate to platform', () async {
      final settings = await client.getSettings(serverUrl: 'https://relay.example.com');
      final updateMessage = await client.updateSettings(
        'https://relay.example.com',
        RelayClientSettings(
          minPairs: 1,
          basePairs: 2,
          maxPairs: 3,
          keepAliveIntervalSeconds: 300,
          acquisitionWaitTime: 30,
        ),
      );
      final diagnostics =
          await client.getKeepAliveDiagnostics('https://relay.example.com');

      expect(settings.basePairs, fakePlatform.getSettingsResult.basePairs);
      expect(updateMessage, fakePlatform.updateSettingsResult);
      expect(diagnostics.raw, fakePlatform.getKeepAliveDiagnosticsResult.raw);
      expect(fakePlatform.getSettingsCallCount, 1);
      expect(fakePlatform.updateSettingsCallCount, 1);
      expect(fakePlatform.getKeepAliveDiagnosticsCallCount, 1);
    });

    test('events passthrough', () async {
      final emitted = <RelayOperationEvent>[];
      final subscription = client.events.listen(emitted.add);

      fakePlatform.simulateEvent(
        RelayOperationEvent(
          type: RelayOperationEventType.uploadProgress,
          bytesCompleted: 1,
          totalBytes: 2,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(emitted.length, 1);
      expect(emitted.single.type, RelayOperationEventType.uploadProgress);
      await subscription.cancel();
    });
  });
}
