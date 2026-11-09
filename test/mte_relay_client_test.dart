import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
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

    // A relay refusal as Android reports it: the relay's status, and the registry reason
    // in X-MTE-Relay-Error among the headers.
    Future<Object?> refusal(int status, {String? header, String? reason, String? outcome}) async {
      final stream = client.stream(RelayRequest(
        serverUrl: 'https://relay.example.com',
        method: 'GET',
        route: '/x',
      ));
      driveStream([
        RelayOperationEvent(
          type: RelayOperationEventType.sseError,
          streamId: fakePlatform.startStreamResult,
          statusCode: status,
          headers: header == null ? const {} : {'X-MTE-Relay-Error': [header]},
          reason: reason,
          outcome: outcome,
          message: 'refused',
        ),
      ]);
      try {
        await stream.drain<void>();
        return null;
      } catch (e) {
        return e;
      }
    }

    test('a replace-pair refusal is a retryable typed exception carrying its reason', () async {
      final error = await refusal(470, header: '470 pair_not_found');
      expect(error, isA<PairReplacedRetryableException>());
      expect((error as RelayException).reason, 'pair_not_found');
      expect(error.statusCode, 470);
    });

    test('a forgotten session is a full repair, keyed on the reason', () async {
      expect(await refusal(475, header: '475 invalid_client_id'),
          isA<FullRepairCompletedRetryableException>());
      // Same status, a revoked key: nothing to retry.
      final revoked = await refusal(475, header: '475 unknown_key');
      expect(revoked.runtimeType, RelayException);
    });

    test("the relay's 481 and a proxy's 413 can be told apart", () async {
      final relay = await refusal(481, header: '481 body_too_large') as RelayException;
      final proxy = await refusal(413) as RelayException;
      expect(relay.reason, 'body_too_large');
      expect(relay.statusCode, 481);
      expect(proxy.reason, isNull);
      expect(proxy.statusCode, 413);
    });

    test('the previous protocol\'s 559 is no longer a typed refusal', () async {
      expect((await refusal(559)).runtimeType, RelayException);
    });

    test('an outcome the platform reports decides the type', () async {
      expect(await refusal(475, outcome: 'fullRepairSuccess'),
          isA<FullRepairCompletedRetryableException>());
      expect(await refusal(470, outcome: 'pairReplaceFailed'), isA<PairReplaceFailedException>());
      final tooLarge = await refusal(481, reason: 'body_too_large') as RelayException;
      expect(tooLarge.reason, 'body_too_large');
    });

    test('a refused start is the same typed exception, not a PlatformException', () async {
      fakePlatform.startStreamError = PlatformException(
        code: 'RELAY_ERROR',
        message: 'repaired',
        details: {'statusCode': 475, 'outcome': 'fullRepairSuccess'},
      );
      final stream = client.stream(RelayRequest(
        serverUrl: 'https://relay.example.com',
        method: 'GET',
        route: '/x',
      ));
      await expectLater(stream.drain<void>(), throwsA(isA<FullRepairCompletedRetryableException>()));
    });

    // A repair or settings change ends with an untagged `completed` on the same
    // bus. Before the fix it ended every open stream: status 0, no error.
    RelayOperationEvent untaggedCompleted() => RelayOperationEvent(
          type: RelayOperationEventType.completed,
          message: 'Relay Response: true Re-pair completed',
        );

    test('an untagged event does not end an open stream', () async {
      final future = client.send(RelayRequest(
        serverUrl: 'https://relay.example.com',
        method: 'GET',
        route: '/echo',
      ));
      driveStream([untaggedCompleted(), opened(200), data('ok'), completed()]);

      final response = await future;
      expect(response.statusCode, 200);
      expect(response.decodeBodyBase64ToUtf8(), 'ok');
    });

    test('an untagged event before the streamId is known is not replayed', () async {
      fakePlatform.startStreamGate = Completer<void>();
      final future = client.send(RelayRequest(
        serverUrl: 'https://relay.example.com',
        method: 'GET',
        route: '/echo',
      ));
      await Future<void>.delayed(Duration.zero);
      fakePlatform.simulateEvent(untaggedCompleted());
      await Future<void>.delayed(Duration.zero);
      fakePlatform.startStreamGate!.complete();
      driveStream([opened(200), data('ok'), completed()]);

      final response = await future;
      expect(response.statusCode, 200);
      expect(response.decodeBodyBase64ToUtf8(), 'ok');
    });

    test('send throws when the stream ends without a response', () async {
      final future = client.send(RelayRequest(
        serverUrl: 'https://relay.example.com',
        method: 'GET',
        route: '/echo',
      ));
      driveStream([completed()]);

      await expectLater(future, throwsA(isA<RelayException>()));
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
