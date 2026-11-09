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

import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'mte_relay_method_channel.dart';
import 'relay_models.dart';

abstract class MteRelayClientPluginPlatform extends PlatformInterface {

  MteRelayClientPluginPlatform() : super(token: _token);

  static final Object _token = Object();

  static MteRelayClientPluginPlatform _instance =
      MethodChannelMteRelayClientPlugin();

  static MteRelayClientPluginPlatform get instance => _instance;

  static set instance(MteRelayClientPluginPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

   Stream<String> get relayResponseStream;
   Stream<dynamic> get relayStreamResponseStream;
   Stream<String> get relayRequestChunksStream;
   Stream<String> get relayStreamCompletionStream;
   Stream<RelayOperationEvent> get events;

  Future<void> initialize() async {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  Future<String> startUpload(RelayFileUploadRequest request) async {
    throw UnimplementedError('startUpload() has not been implemented.');
  }

  Future<String> startDownload(RelayFileDownloadRequest request) async {
    throw UnimplementedError('startDownload() has not been implemented.');
  }

  Future<bool> cancelOperation(String operationId) async {
    throw UnimplementedError('cancelOperation() has not been implemented.');
  }

  /// Starts a streaming request on the native side and returns its streamId;
  /// response events arrive on [events] tagged with that id.
  Future<String> startStream(RelayRequest request) async {
    throw UnimplementedError('startStream() has not been implemented.');
  }

  Future<bool> cancelStream(String streamId) async {
    throw UnimplementedError('cancelStream() has not been implemented.');
  }

  Future<void> repair(String serverUrl, {String? pathnamePrefix}) async {
    throw UnimplementedError('repair() has not been implemented.');
  }

  Future<RelayClientSettings> getSettings({
    required String serverUrl,
    String? pathnamePrefix,
  }) async {
    throw UnimplementedError('getSettings() has not been implemented.');
  }

  Future<String> updateSettings(
    String serverUrl,
    RelayClientSettings settings, {
    String? pathnamePrefix,
  }) async {
    throw UnimplementedError('updateSettings() has not been implemented.');
  }

  Future<RelayKeepAliveDiagnostics> getKeepAliveDiagnostics(
    String serverUrl,
  ) async {
    throw UnimplementedError(
      'getKeepAliveDiagnostics() has not been implemented.',
    );
  }

  Future<void> enableRelayFileLogging(bool enabled) async {
    throw UnimplementedError(
      'enableRelayFileLogging() has not been implemented.',
    );
  }

  Future<String> readRelayLogFile() async {
    throw UnimplementedError('readRelayLogFile() has not been implemented.');
  }

  Future<void> clearRelayLogFile() async {
    throw UnimplementedError('clearRelayLogFile() has not been implemented.');
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<void> initializeRelay() async {
    throw UnimplementedError('initializeRelay() has not been implemented.');
  }





  Future<void> sendChunk(dynamic args) async {
    throw UnimplementedError('sendChunk() has not been implemented.');
  }

  Future<void> closeStream(dynamic args) async {
    throw UnimplementedError('closeStream() has not been implemented.');
  }

  Future<String> enableFileLogging(bool isEnabled) async {
    throw UnimplementedError('enableFileLogging() has not been implemented.');
  }

  Future<String> readLogFile() async {
    throw UnimplementedError('readLogFile() has not been implemented.');
  }

  Future<String> clearLogFile() async {
    throw UnimplementedError('clearLogFile() has not been implemented.');
  }
}
