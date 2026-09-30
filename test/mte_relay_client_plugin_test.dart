import 'package:flutter_test/flutter_test.dart';
import 'package:mte_relay/mte_relay.dart';
import 'package:mte_relay/mte_relay_platform_interface.dart';

import 'helpers/fake_mte_relay_client_plugin_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MteRelayClientPlugin', () {
    late MteRelayClientPluginPlatform originalPlatform;
    late FakeMteRelayClientPluginPlatform fakePlatform;
    late MteRelayClientPlugin plugin;

    setUp(() {
      originalPlatform = MteRelayClientPluginPlatform.instance;
      fakePlatform = FakeMteRelayClientPluginPlatform();
      MteRelayClientPluginPlatform.instance = fakePlatform;
      plugin = MteRelayClientPlugin();
    });

    tearDown(() async {
      MteRelayClientPluginPlatform.instance = originalPlatform;
      await fakePlatform.dispose();
    });

    test('getPlatformVersion should delegate to platform instance', () async {
      final version = await plugin.getPlatformVersion();

      expect(version, '42');
      expect(fakePlatform.getPlatformVersionCallCount, 1);
    });

    test('initializeRelay should delegate to platform instance', () async {
      await plugin.initializeRelay();

      expect(fakePlatform.initializeRelayCallCount, 1);
    });


    test('sendChunk should delegate args', () async {
      await plugin.sendChunk({'streamID': 's1', 'data': [1, 2, 3]});

      expect(fakePlatform.sendChunkCallCount, 1);
      expect(fakePlatform.lastSendChunkArgs, {'streamID': 's1', 'data': [1, 2, 3]});
    });

    test('closeStream should delegate args', () async {
      await plugin.closeStream({'streamID': 's1'});

      expect(fakePlatform.closeStreamCallCount, 1);
      expect(fakePlatform.lastCloseStreamArgs, {'streamID': 's1'});
    });

    test('enableFileLogging should delegate args and return result', () async {
      final result = await plugin.enableFileLogging(true);

      expect(fakePlatform.enableFileLoggingCallCount, 1);
      expect(fakePlatform.lastEnableFileLoggingIsEnabled, isTrue);
      expect(result, fakePlatform.enableFileLoggingResult);
    });

    test('readLogFile should delegate args and return result', () async {
      final result = await plugin.readLogFile();

      expect(fakePlatform.readLogFileCallCount, 1);
      expect(result, fakePlatform.readLogFileResult);
    });

    test('clearLogFile should delegate args and return result', () async {
      final result = await plugin.clearLogFile();

      expect(fakePlatform.clearLogFileCallCount, 1);
      expect(result, fakePlatform.clearLogFileResult);
    });

    test('relayResponseStream should pass through platform events', () async {
      final emitted = <String>[];
      final subscription = plugin.relayResponseStream.listen(emitted.add);

      fakePlatform.simulateRelayResponse('ready');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, ['ready']);
      await subscription.cancel();
    });

    test('relayStreamResponseStream should pass through platform events', () async {
      final emitted = <dynamic>[];
      final subscription = plugin.relayStreamResponseStream.listen(emitted.add);

      fakePlatform.simulateRelayStreamResponse({'statusCode': 200, 'data': 'ok'});
      await Future<void>.delayed(Duration.zero);

      expect(emitted, [
        {'statusCode': 200, 'data': 'ok'},
      ]);
      await subscription.cancel();
    });

    test('relayRequestChunksStream should pass through platform events', () async {
      final emitted = <String>[];
      final subscription = plugin.relayRequestChunksStream.listen(emitted.add);

      fakePlatform.simulateRelayRequestChunks('stream-2');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, ['stream-2']);
      await subscription.cancel();
    });

    test('relayStreamCompletionStream should pass through platform events', () async {
      final emitted = <String>[];
      final subscription = plugin.relayStreamCompletionStream.listen(emitted.add);

      fakePlatform.simulateRelayStreamCompletion('0.5');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, ['0.5']);
      await subscription.cancel();
    });

  });
}
