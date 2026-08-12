import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mte_relay/mte_relay.dart';
import 'package:mte_relay/mte_relay_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// A platform double that captures the [RelayRequest] the client sends and
/// replays a scripted sequence of relay events once the client has subscribed
/// and learned the streamId — mirroring how the native side drives the bus.
class _FakePlatform extends MteRelayClientPluginPlatform
    with MockPlatformInterfaceMixin {
  _FakePlatform(this.script);

  final List<RelayOperationEvent> script;
  final _events = StreamController<RelayOperationEvent>.broadcast();
  RelayRequest? captured;
  int cancelCount = 0;
  String streamId = 'stream-1';

  @override
  Stream<RelayOperationEvent> get events => _events.stream;

  // Unused legacy streams the abstract interface still requires.
  @override
  Stream<String> get relayResponseStream => const Stream.empty();
  @override
  Stream<dynamic> get relayStreamResponseStream => const Stream.empty();
  @override
  Stream<String> get relayRequestChunksStream => const Stream.empty();
  @override
  Stream<String> get relayStreamCompletionStream => const Stream.empty();

  @override
  Future<String> startStream(RelayRequest request) async {
    captured = request;
    scheduleMicrotask(() {
      for (final event in script) {
        _events.add(event);
      }
    });
    return streamId;
  }

  @override
  Future<bool> cancelStream(String id) async {
    cancelCount++;
    return true;
  }

  void dispose() => _events.close();
}

RelayOperationEvent _opened(int status,
        {Map<String, List<String>> headers = const {}}) =>
    RelayOperationEvent(
      type: RelayOperationEventType.sseOpened,
      streamId: 'stream-1',
      statusCode: status,
      headers: headers,
    );

RelayOperationEvent _data(String text) => RelayOperationEvent(
      type: RelayOperationEventType.sseData,
      streamId: 'stream-1',
      dataBase64: base64Encode(utf8.encode(text)),
    );

RelayOperationEvent _completed() => RelayOperationEvent(
      type: RelayOperationEventType.sseCompleted,
      streamId: 'stream-1',
    );

RelayOperationEvent _error(int status, String message) => RelayOperationEvent(
      type: RelayOperationEventType.sseError,
      streamId: 'stream-1',
      statusCode: status,
      message: message,
    );

void main() {
  late _FakePlatform platform;

  void install(List<RelayOperationEvent> script) {
    platform = _FakePlatform(script);
    MteRelayClientPluginPlatform.instance = platform;
  }

  tearDown(() => platform.dispose());

  test('post buffers the streamed chunks into one Response', () async {
    install([_opened(200), _data('{"ok":'), _data('true}'), _completed()]);
    final client = RelayHttpClient();

    final response = await client.post(
      Uri.parse('https://relay.example.com/api/login'),
      headers: {'content-type': 'application/json'},
      body: '{"email":"a@b.c"}',
    );

    expect(response.statusCode, 200);
    expect(response.body, '{"ok":true}');
  });

  test('maps the request URL onto origin + route and forwards the body',
      () async {
    install([_opened(200), _completed()]);
    final client = RelayHttpClient();

    await client.post(
      Uri.parse('https://relay.example.com/api/items?page=2'),
      headers: {'content-type': 'application/json'},
      body: 'payload',
    );

    final captured = platform.captured!;
    expect(captured.serverUrl, 'https://relay.example.com');
    expect(captured.route, '/api/items?page=2');
    expect(captured.method, 'POST');
    expect(utf8.decode(captured.body!), 'payload');
  });

  test('send exposes the decrypted chunks incrementally, in order', () async {
    install([_opened(200), _data('a'), _data('b'), _data('c'), _completed()]);
    final client = RelayHttpClient();

    final streamed = await client.send(
      http.Request('GET', Uri.parse('https://relay.example.com/events')),
    );

    final chunks = <String>[];
    await for (final chunk in streamed.stream) {
      chunks.add(utf8.decode(chunk));
    }
    expect(chunks, ['a', 'b', 'c']);
    expect(streamed.statusCode, 200);
  });

  test('flattens multi-valued response headers', () async {
    install([
      _opened(201, headers: {
        'set-cookie': ['a=1', 'b=2'],
        'content-type': ['text/plain'],
      }),
      _completed(),
    ]);
    final client = RelayHttpClient();

    final response =
        await client.get(Uri.parse('https://relay.example.com/x'));

    expect(response.statusCode, 201);
    expect(response.headers['set-cookie'], 'a=1, b=2');
    expect(response.headers['content-type'], 'text/plain');
  });

  test('a relay failure surfaces as an http.ClientException (typed relay errors '
      'live on the lower-level stream/send API)', () async {
    install([_error(559, 'pair desynced')]);
    final client = RelayHttpClient();

    await expectLater(
      client.get(Uri.parse('https://relay.example.com/x')),
      throwsA(
        isA<http.ClientException>().having(
          (e) => e.message,
          'message',
          contains('pair desynced'),
        ),
      ),
    );
  });

  test('a non-repair failure before the response opens throws ClientException',
      () async {
    install([_error(-1, 'network down')]);
    final client = RelayHttpClient();

    await expectLater(
      client.get(Uri.parse('https://relay.example.com/x')),
      throwsA(isA<http.ClientException>()),
    );
  });

  test('a failure mid-stream surfaces as an error on the body stream',
      () async {
    install([_opened(200), _data('partial'), _error(500, 'upstream blew up')]);
    final client = RelayHttpClient();

    final streamed = await client.send(
      http.Request('GET', Uri.parse('https://relay.example.com/events')),
    );

    final seen = <String>[];
    await expectLater(
      streamed.stream.map(utf8.decode).forEach(seen.add),
      throwsA(isA<http.ClientException>()),
    );
    expect(seen, ['partial']);
  });

  test('abandoning the response stream cancels the relay stream', () async {
    install([_opened(200), _data('one')]); // never completes on its own
    final client = RelayHttpClient();

    final streamed = await client.send(
      http.Request('GET', Uri.parse('https://relay.example.com/events')),
    );
    final sub = streamed.stream.listen((_) {});
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(platform.cancelCount, 1);
  });
}
