import 'package:flutter_test/flutter_test.dart';
import 'package:mte_relay/mte_relay_method_channel.dart';
import 'package:mte_relay/mte_relay_platform_interface.dart';
import 'package:mte_relay/relay_models.dart';

import 'helpers/fake_mte_relay_client_plugin_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MteRelayClientPluginPlatform', () {
    late MteRelayClientPluginPlatform original;

    setUp(() {
      original = MteRelayClientPluginPlatform.instance;
    });

    tearDown(() {
      MteRelayClientPluginPlatform.instance = original;
    });

    test('default instance should be method channel implementation', () {
      expect(
        MteRelayClientPluginPlatform.instance,
        isA<MethodChannelMteRelayClientPlugin>(),
      );
    });

    test('instance setter should accept valid platform implementation', () {
      final fake = FakeMteRelayClientPluginPlatform();
      MteRelayClientPluginPlatform.instance = fake;

      expect(MteRelayClientPluginPlatform.instance, same(fake));
    });

    test('instance setter should reject platform without token', () {
      final invalid = _InvalidPlatform();

      expect(
        () => MteRelayClientPluginPlatform.instance = invalid,
        throwsA(isA<AssertionError>()),
      );
    });

    test('base methods should throw UnimplementedError by default', () async {
      final platform = _BaseContractPlatform();

      expect(platform.relayResponseStream, isA<Stream<String>>());
      expect(platform.relayStreamResponseStream, isA<Stream<dynamic>>());
      expect(platform.relayRequestChunksStream, isA<Stream<String>>());
      expect(platform.relayStreamCompletionStream, isA<Stream<String>>());

      expect(() => platform.getPlatformVersion(), throwsUnimplementedError);
      expect(platform.initializeRelay(), throwsUnimplementedError);
      expect(platform.relayUploadFile({}), throwsUnimplementedError);
      expect(platform.relayDownloadFile({}), throwsUnimplementedError);
      expect(
        platform.rePair(url: 'https://relay.example.com', pathnamePrefix: null),
        throwsUnimplementedError,
      );
      expect(
        platform.adjustRelaySettings(
          url: 'https://relay.example.com',
          pathnamePrefix: null,
          pairPoolSize: 3,
        ),
        throwsUnimplementedError,
      );
      expect(platform.sendChunk({}), throwsUnimplementedError);
      expect(platform.closeStream({}), throwsUnimplementedError);
      expect(platform.enableFileLogging(true), throwsUnimplementedError);
      expect(platform.readLogFile(), throwsUnimplementedError);
      expect(platform.clearLogFile(), throwsUnimplementedError);
    });
  });
}

class _BaseContractPlatform extends MteRelayClientPluginPlatform {
  @override
  Stream<RelayOperationEvent> get events => const Stream.empty();

  @override
  Stream<String> get relayResponseStream => const Stream.empty();

  @override
  Stream<dynamic> get relayStreamResponseStream => const Stream.empty();

  @override
  Stream<String> get relayRequestChunksStream => const Stream.empty();

  @override
  Stream<String> get relayStreamCompletionStream => const Stream.empty();
}

class _InvalidPlatform implements MteRelayClientPluginPlatform {
  @override
  Stream<RelayOperationEvent> get events => const Stream.empty();

  @override
  Stream<String> get relayResponseStream => const Stream.empty();

  @override
  Stream<dynamic> get relayStreamResponseStream => const Stream.empty();

  @override
  Stream<String> get relayRequestChunksStream => const Stream.empty();

  @override
  Stream<String> get relayStreamCompletionStream => const Stream.empty();

  @override
  Future<void> closeStream(dynamic args) async {}

  @override
  Future<String> adjustRelaySettings({
    required String url,
    String? pathnamePrefix,
    required int pairPoolSize,
  }) async => 'ok';

  @override
  Future<String> clearLogFile() async => 'ok';

  @override
  Future<String> enableFileLogging(bool isEnabled) async => 'ok';

  @override
  Future<String?> getPlatformVersion() async => 'x';

  @override
  Future<void> initializeRelay() async {}

  @override
  Future<String> readLogFile() async => 'ok';

  @override
  Future<String> rePair({required String url, String? pathnamePrefix}) async => 'ok';

  @override
  Future<String> relayDownloadFile(dynamic args) async => 'ok';

  @override
  Future<String> relayUploadFile(dynamic args) async => 'ok';

  @override
  Future<void> sendChunk(dynamic args) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
