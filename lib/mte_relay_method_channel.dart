// The MIT License (MIT)
//
// Copyright (c) Eclypses, Inc.
//
// All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'mte_relay_platform_interface.dart';
import 'relay_models.dart';

/// An implementation of [MteRelayClientPluginPlatform] that uses method channels.
class MethodChannelMteRelayClientPlugin extends MteRelayClientPluginPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('mte_relay_client_plugin');

  @visibleForTesting
  final methodsChannel = const MethodChannel('mte_relay/methods');

  @visibleForTesting
  final eventsChannel = const EventChannel('mte_relay/events');

  /// Constructor to initialize the method call handler
  MethodChannelMteRelayClientPlugin() {
    methodChannel.setMethodCallHandler(_handleNativeCallback);
    eventsChannel.receiveBroadcastStream().listen(
      _handleEventChannelEvent,
      onError: (_) {},
    );
  }

  // SECTION: MethodChannel calls back to Flutter App
  final StreamController<String> _relayResponseStreamController =
      StreamController<String>.broadcast();

  final StreamController<dynamic> _relayStreamResponseStreamController =
      StreamController<dynamic>.broadcast();

  final StreamController<String> _relayRequestChunksStreamController =
      StreamController<String>.broadcast();

  final StreamController<String> _relayStreamCompletionStreamController =
      StreamController<String>.broadcast();

  final StreamController<RelayOperationEvent> _eventsStreamController =
      StreamController<RelayOperationEvent>.broadcast();

  @override
  Stream<RelayOperationEvent> get events => _eventsStreamController.stream;

  @override
  Future<void> initialize() async {
    try {
      await methodsChannel.invokeMethod('initialize');
    } on MissingPluginException {
      await initializeRelay();
    }
  }

  @override
  Future<String> startUpload(RelayFileUploadRequest request) async {
    final operationId = await methodsChannel.invokeMethod<String>(
      'startUpload',
      request.toMap(),
    );
    return operationId ?? '';
  }

  @override
  Future<String> startDownload(RelayFileDownloadRequest request) async {
    final operationId = await methodsChannel.invokeMethod<String>(
      'startDownload',
      request.toMap(),
    );
    return operationId ?? '';
  }

  @override
  Future<bool> cancelOperation(String operationId) async {
    try {
      final cancelled = await methodsChannel.invokeMethod<bool>('cancelOperation', {
        'operationId': operationId,
      });
      return cancelled ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<String> startStream(RelayRequest request) async {
    final streamId = await methodsChannel.invokeMethod<String>(
      'startStream',
      request.toMap(),
    );
    return streamId ?? '';
  }

  @override
  Future<bool> cancelStream(String streamId) async {
    final cancelled = await methodsChannel.invokeMethod<bool>('cancelStream', {
      'streamId': streamId,
    });
    return cancelled ?? false;
  }

  @override
  Future<void> repair(String serverUrl, {String? pathnamePrefix}) async {
    await methodsChannel.invokeMethod('repair', {
      'serverUrl': serverUrl,
      'pathnamePrefix': pathnamePrefix,
    });
  }

  @override
  Future<RelayClientSettings> getSettings({
    required String serverUrl,
    String? pathnamePrefix,
  }) async {
    final settings = await methodsChannel
        .invokeMapMethod<dynamic, dynamic>(
          'getSettings',
          {
            'serverUrl': serverUrl,
            'pathnamePrefix': pathnamePrefix,
          },
        )
        .timeout(
          const Duration(seconds: 12),
          onTimeout: () => throw TimeoutException(
            'Timed out waiting for native getSettings response.',
          ),
        );
    return RelayClientSettings.fromMap(settings ?? const <dynamic, dynamic>{});
  }

  @override
  Future<String> updateSettings(
    String serverUrl,
    RelayClientSettings settings, {
    String? pathnamePrefix,
  }) async {
    settings.validate();
    final response = await methodsChannel
        .invokeMethod<String>('updateSettings', {
          'serverUrl': serverUrl,
          'pathnamePrefix': pathnamePrefix,
          'settings': settings.toMap(),
        })
        .timeout(
          const Duration(seconds: 12),
          onTimeout: () => throw TimeoutException(
            'Timed out waiting for native updateSettings acknowledgement.',
          ),
        );
    return response ?? '';
  }

  @override
  Future<RelayKeepAliveDiagnostics> getKeepAliveDiagnostics(
    String serverUrl,
  ) async {
    final diagnostics = await methodsChannel.invokeMethod<String>(
      'getKeepAliveDiagnostics',
      {
        'serverUrl': serverUrl,
      },
    );
    return RelayKeepAliveDiagnostics(
      serverUrl: serverUrl,
      raw: diagnostics ?? '',
    );
  }

  @override
  Future<void> enableRelayFileLogging(bool enabled) async {
    try {
      await methodsChannel.invokeMethod('enableFileLogging', {'enabled': enabled});
    } on MissingPluginException {
      await enableFileLogging(enabled);
    }
  }

  @override
  Future<String> readRelayLogFile() async {
    try {
      final data = await methodsChannel.invokeMethod<String>('readLogFile');
      return data ?? '';
    } on MissingPluginException {
      return readLogFile();
    }
  }

  @override
  Future<void> clearRelayLogFile() async {
    try {
      await methodsChannel.invokeMethod('clearLogFile');
    } on MissingPluginException {
      await clearLogFile();
    }
  }

  // SECTION: MethodChannel calls to native
  @override
  Future<void> initializeRelay() async {
    await methodChannel.invokeMethod('initializeRelay');
  }





  @override
  Future<String> sendChunk(dynamic args) async {
    return await methodChannel.invokeMethod('writeToStream', args);
  }

  @override
  Future<String> closeStream(dynamic args) async {
    return await methodChannel.invokeMethod('closeStream', args);
  }

  @override
  Future<String> enableFileLogging(bool isEnabled) async {
    return await methodChannel.invokeMethod('enableFileLogging', isEnabled);
  }

  @override
  Future<String> readLogFile() async {
    return await methodChannel.invokeMethod('readLogFile');
  }

  @override
  Future<String> clearLogFile() async {
    return await methodChannel.invokeMethod('clearLogFile');
  }


  // SECTION: Listeners for calls back from native
  Future<dynamic> _handleNativeCallback(MethodCall call) async {
    switch (call.method) {
      case "getFileStream":
        String streamID = call.arguments;
        _relayRequestChunksStreamController.add(streamID);
        return Future.value(null);

      case "relayResponseMessage":
        String message = call.arguments;
        _relayResponseStreamController.add(message);
        return Future.value(message);

      case "streamCompletionPercentage":
        double progress = call.arguments;
        _relayStreamCompletionStreamController.add(progress.toString());
        return Future.value(progress.toString());

      case "relayStreamResponse":
        _relayStreamResponseStreamController.add(call.arguments);
        return Future.value(call.arguments);
    }
  }

  void _handleEventChannelEvent(dynamic event) {
    if (event is Map) {
      _eventsStreamController.add(
        RelayOperationEvent.fromMap(event),
      );
    }
  }


  
  @override
  Stream<String> get relayResponseStream =>
      _relayResponseStreamController.stream;

  @override
  Stream<dynamic> get relayStreamResponseStream =>
      _relayStreamResponseStreamController.stream;

  @override
  Stream<String> get relayRequestChunksStream =>
      _relayRequestChunksStreamController.stream;

  @override
  Stream<String> get relayStreamCompletionStream =>
      _relayStreamCompletionStreamController.stream;
}
