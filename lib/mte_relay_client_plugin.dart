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
import 'mte_relay_client_plugin_platform_interface.dart';

export 'mte_relay_client.dart';
export 'relay_exceptions.dart';
export 'relay_http_client.dart';
export 'relay_models.dart';

class MteRelayClientPlugin {
  
  // SECTION: Calls to ative
  Future<String?> getPlatformVersion() {
    return MteRelayClientPluginPlatform.instance.getPlatformVersion();
  }

  Future<void> initializeRelay() {
    return MteRelayClientPluginPlatform.instance.initializeRelay();
  }

  Future<String> relayUploadFile(dynamic args) {
    return MteRelayClientPluginPlatform.instance.relayUploadFile(args);
  }

  Future<String> relayDownloadFile(dynamic args) {
    return MteRelayClientPluginPlatform.instance.relayDownloadFile(args);
  }

  Future<String> rePair({required String url, String? pathnamePrefix}) {
    return MteRelayClientPluginPlatform.instance.rePair(
      url: url,
      pathnamePrefix: pathnamePrefix,
    );
  }

  Future<String> adjustRelaySettings({
    required String url,
    String? pathnamePrefix,
    required int pairPoolSize,
  }) {
    return MteRelayClientPluginPlatform.instance.adjustRelaySettings(
      url: url,
      pathnamePrefix: pathnamePrefix,
      pairPoolSize: pairPoolSize,
    );
  }

  Future<void> sendChunk(dynamic args) {
    return MteRelayClientPluginPlatform.instance.sendChunk(args);
  }

  Future<void> closeStream(dynamic args) {
    return MteRelayClientPluginPlatform.instance.closeStream(args);
  }

  Future<String> enableFileLogging(bool isEnabled) {
    return MteRelayClientPluginPlatform.instance.enableFileLogging(isEnabled);
  }

  Future<String> readLogFile() {
    return MteRelayClientPluginPlatform.instance.readLogFile();
  }

  Future<String> clearLogFile() {
    return MteRelayClientPluginPlatform.instance.clearLogFile();
  }

  // SECTION: Callback methods to Flutter App.
  Stream<String> get relayResponseStream =>
      MteRelayClientPluginPlatform.instance.relayResponseStream;

  Stream<dynamic> get relayStreamResponseStream =>
      MteRelayClientPluginPlatform.instance.relayStreamResponseStream;

  Stream<String> get relayRequestChunksStream =>
      MteRelayClientPluginPlatform.instance.relayRequestChunksStream;

  Stream<String> get relayStreamCompletionStream =>
      MteRelayClientPluginPlatform.instance.relayStreamCompletionStream;

}
