import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mte_relay/mte_relay_method_channel.dart';
import 'package:mte_relay/relay_models.dart';

import 'fixtures/test_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('mte_relay_client_plugin');
  const MethodChannel typedMethodsChannel = MethodChannel('mte_relay/methods');
  const MethodChannel typedEventsControlChannel = MethodChannel('mte_relay/events');
  final List<MethodCall> nativeCalls = <MethodCall>[];
  final List<MethodCall> typedCalls = <MethodCall>[];

  late MethodChannelMteRelayClientPlugin plugin;

  setUp(() {
    nativeCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          nativeCalls.add(call);
          switch (call.method) {
            case 'initializeRelay':
              return null;
            default:
              return 'ok';
          }
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(typedMethodsChannel, (MethodCall call) async {
          typedCalls.add(call);
          switch (call.method) {
            case 'initialize':
              return null;
            case 'startUpload':
              return 'upload-op-1';
            case 'startDownload':
              return 'download-op-1';
            case 'cancelOperation':
              return true;
            case 'cancelStream':
              return true;
            case 'startStream':
              return 'sse-op-1';
            case 'getSettings':
              return {
                'minPairs': 1,
                'basePairs': 2,
                'maxPairs': 3,
                'keepAliveIntervalSeconds': 300,
                'acquisitionWaitTime': 30.0,
              };
            case 'updateSettings':
              return 'settings-updated';
            case 'getKeepAliveDiagnostics':
              return 'healthy';
            default:
              return 'ok';
          }
        });

    // EventChannel control calls use MethodChannel semantics for listen/cancel.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          typedEventsControlChannel,
          (MethodCall call) async => null,
        );

    plugin = MethodChannelMteRelayClientPlugin();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(typedMethodsChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(typedEventsControlChannel, null);
  });

  group('typed channel calls', () {
    test('initialize should invoke initialize on typed channel', () async {
      await plugin.initialize();

      expect(typedCalls.single.method, 'initialize');
    });

    test('startStream should invoke startStream on the typed channel', () async {
      await plugin.startStream(
        RelayRequest(
          serverUrl: 'https://relay.example.com',
          method: 'GET',
          route: '/api/events',
        ),
      );

      expect(typedCalls.any((call) => call.method == 'startStream'), isTrue);
    });

    test('events stream should decode relay event envelope', () async {
      final emitted = <RelayOperationEvent>[];
      final subscription = plugin.events.listen(emitted.add);

      await _emitTypedEventEnvelope({
        'type': 'sseData',
        'streamId': 'stream-1',
        'message': 'delta',
      });

      expect(emitted.length, 1);
      expect(emitted.single.type, RelayOperationEventType.sseData);
      expect(emitted.single.streamId, 'stream-1');
      expect(emitted.single.message, 'delta');
      await subscription.cancel();
    });
  });

  group('outgoing native calls', () {
    test('initializeRelay should invoke initializeRelay method', () async {
      await plugin.initializeRelay();

      expect(nativeCalls.single.method, 'initializeRelay');
      expect(nativeCalls.single.arguments, isNull);
    });

    test('relayUploadFile should invoke relayUploadFile', () async {
      final result = await plugin.relayUploadFile(testArgs);

      expect(nativeCalls.single.method, 'relayUploadFile');
      expect(nativeCalls.single.arguments, testArgs);
      expect(result, 'ok');
    });

    test('relayDownloadFile should invoke relayDownloadFile', () async {
      final result = await plugin.relayDownloadFile(testArgs);

      expect(nativeCalls.single.method, 'relayDownloadFile');
      expect(nativeCalls.single.arguments, testArgs);
      expect(result, 'ok');
    });

    test('rePair should invoke rePair', () async {
      final result = await plugin.rePair(
        url: 'https://relay.example.com',
        pathnamePrefix: '/prefix',
      );

      expect(nativeCalls.single.method, 'rePair');
      expect(nativeCalls.single.arguments, {
        'url': 'https://relay.example.com',
        'pathnamePrefix': '/prefix',
      });
      expect(result, 'ok');
    });

    test('adjustRelaySettings should invoke adjustRelaySettings', () async {
      final result = await plugin.adjustRelaySettings(
        url: 'https://relay.example.com',
        pathnamePrefix: '/prefix',
        pairPoolSize: 3,
      );

      expect(nativeCalls.single.method, 'adjustRelaySettings');
      expect(nativeCalls.single.arguments, {
        'url': 'https://relay.example.com',
        'pathnamePrefix': '/prefix',
        'pairPoolSize': 3,
      });
      expect(result, 'ok');
    });

    test('sendChunk should invoke writeToStream', () async {
      final result = await plugin.sendChunk({'streamID': 's1', 'data': [1, 2, 3]});

      expect(nativeCalls.single.method, 'writeToStream');
      expect(nativeCalls.single.arguments, {'streamID': 's1', 'data': [1, 2, 3]});
      expect(result, 'ok');
    });

    test('closeStream should invoke closeStream', () async {
      final result = await plugin.closeStream({'streamID': 's1'});

      expect(nativeCalls.single.method, 'closeStream');
      expect(nativeCalls.single.arguments, {'streamID': 's1'});
      expect(result, 'ok');
    });

    test('enableFileLogging should invoke enableFileLogging', () async {
      final result = await plugin.enableFileLogging(true);

      expect(nativeCalls.single.method, 'enableFileLogging');
      expect(nativeCalls.single.arguments, true);
      expect(result, 'ok');
    });

    test('readLogFile should invoke readLogFile', () async {
      final result = await plugin.readLogFile();

      expect(nativeCalls.single.method, 'readLogFile');
      expect(nativeCalls.single.arguments, isNull);
      expect(result, 'ok');
    });

    test('clearLogFile should invoke clearLogFile', () async {
      final result = await plugin.clearLogFile();

      expect(nativeCalls.single.method, 'clearLogFile');
      expect(nativeCalls.single.arguments, isNull);
      expect(result, 'ok');
    });
  });

  group('incoming native callbacks', () {
    test('should emit stream id on getFileStream callback', () async {
      final emitted = <String>[];
      final subscription = plugin.relayRequestChunksStream.listen(emitted.add);

      await _invokeNativeCallback('getFileStream', 'stream-1');

      expect(emitted, ['stream-1']);
      await subscription.cancel();
    });

    test('should emit message on relayResponseMessage callback', () async {
      final emitted = <String>[];
      final subscription = plugin.relayResponseStream.listen(emitted.add);

      await _invokeNativeCallback('relayResponseMessage', 'connected');

      expect(emitted, ['connected']);
      await subscription.cancel();
    });

    test('should emit progress string on streamCompletionPercentage callback', () async {
      final emitted = <String>[];
      final subscription = plugin.relayStreamCompletionStream.listen(emitted.add);

      await _invokeNativeCallback('streamCompletionPercentage', 0.75);

      expect(emitted, ['0.75']);
      await subscription.cancel();
    });

    test('should emit payload on relayStreamResponse callback', () async {
      final payload = {'statusCode': 201, 'data': 'created'};
      final emitted = <dynamic>[];
      final subscription = plugin.relayStreamResponseStream.listen(emitted.add);

      await _invokeNativeCallback('relayStreamResponse', payload);

      expect(emitted, [payload]);
      await subscription.cancel();
    });

    test('streams should be broadcast to multiple listeners', () async {
      final first = <String>[];
      final second = <String>[];
      final firstSubscription = plugin.relayResponseStream.listen(first.add);
      final secondSubscription = plugin.relayResponseStream.listen(second.add);

      await _invokeNativeCallback('relayResponseMessage', 'first');
      await _invokeNativeCallback('relayResponseMessage', 'second');

      expect(first, ['first', 'second']);
      expect(second, ['first', 'second']);

      await firstSubscription.cancel();
      await secondSubscription.cancel();
    });
  });
}

Future<void> _invokeNativeCallback(String method, [dynamic arguments]) async {
  const channelName = 'mte_relay_client_plugin';
  const codec = StandardMethodCodec();
  final ByteData message = codec.encodeMethodCall(MethodCall(method, arguments));

  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(channelName, message, (_) {});

  await Future<void>.delayed(Duration.zero);
}

Future<void> _emitTypedEventEnvelope(dynamic event) async {
  const channelName = 'mte_relay/events';
  const codec = StandardMethodCodec();
  final ByteData message = codec.encodeSuccessEnvelope(event);

  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(channelName, message, (_) {});

  await Future<void>.delayed(Duration.zero);
}
