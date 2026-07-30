import 'dart:async';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:mte_relay_client_plugin/mte_relay_client_plugin_platform_interface.dart';
import 'package:mte_relay_client_plugin/relay_models.dart';

class FakeMteRelayClientPluginPlatform extends MteRelayClientPluginPlatform
    with MockPlatformInterfaceMixin {
  String? platformVersion = '42';

  String relayUploadFileResult = 'upload-ok';
  String relayDownloadFileResult = 'download-ok';
  String rePairResult = 'repair-ok';
  String adjustRelaySettingsResult = 'adjust-ok';
  String enableFileLoggingResult = 'logging-ok';
  String readLogFileResult = 'log-content';
  String clearLogFileResult = 'clear-ok';
  String startUploadResult = 'upload-op-1';
  String startDownloadResult = 'download-op-1';
  bool cancelOperationResult = true;
  String startStreamResult = 'sse-op-1';
  bool cancelStreamResult = true;
  RelayClientSettings getSettingsResult = RelayClientSettings(
    minPairs: 1,
    basePairs: 2,
    maxPairs: 3,
    keepAliveIntervalSeconds: 300,
    acquisitionWaitTime: 30,
  );
  String updateSettingsResult = 'update-ok';
  RelayKeepAliveDiagnostics getKeepAliveDiagnosticsResult =
      RelayKeepAliveDiagnostics(
    serverUrl: 'https://relay.example.com',
    raw: 'healthy',
  );

  int getPlatformVersionCallCount = 0;
  int initializeRelayCallCount = 0;
  int relayUploadFileCallCount = 0;
  int relayDownloadFileCallCount = 0;
  int rePairCallCount = 0;
  int adjustRelaySettingsCallCount = 0;
  int sendChunkCallCount = 0;
  int closeStreamCallCount = 0;
  int enableFileLoggingCallCount = 0;
  int readLogFileCallCount = 0;
  int clearLogFileCallCount = 0;
  int initializeCallCount = 0;
  int startUploadCallCount = 0;
  int startDownloadCallCount = 0;
  int cancelOperationCallCount = 0;
  int startStreamCallCount = 0;
  int cancelStreamCallCount = 0;
  int repairCallCount = 0;
  int getSettingsCallCount = 0;
  int updateSettingsCallCount = 0;
  int getKeepAliveDiagnosticsCallCount = 0;
  int enableRelayFileLoggingCallCount = 0;
  int readRelayLogFileCallCount = 0;
  int clearRelayLogFileCallCount = 0;

  dynamic lastRelayUploadFileArgs;
  dynamic lastRelayDownloadFileArgs;
  String? lastRePairUrl;
  String? lastRePairPathnamePrefix;
  String? lastAdjustRelaySettingsUrl;
  String? lastAdjustRelaySettingsPathnamePrefix;
  int? lastAdjustRelaySettingsPairPoolSize;
  dynamic lastSendChunkArgs;
  dynamic lastCloseStreamArgs;
  bool? lastEnableFileLoggingIsEnabled;
  RelayFileUploadRequest? lastStartUploadRequest;
  RelayFileDownloadRequest? lastStartDownloadRequest;
  String? lastCancelOperationId;
  RelayRequest? lastStartStreamRequest;
  String? lastRepairServerUrl;
  String? lastRepairPathnamePrefix;
  String? lastGetSettingsServerUrl;
  String? lastGetSettingsPathnamePrefix;
  String? lastUpdateSettingsServerUrl;
  String? lastUpdateSettingsPathnamePrefix;
  RelayClientSettings? lastUpdateSettings;
  String? lastKeepAliveServerUrl;

  bool shouldFailInitializeRelay = false;
  bool shouldFailRelayUploadFile = false;
  bool shouldFailRelayDownloadFile = false;
  bool shouldFailRePair = false;
  bool shouldFailAdjustRelaySettings = false;
  bool shouldFailSendChunk = false;
  bool shouldFailCloseStream = false;
  bool shouldFailEnableFileLogging = false;
  bool shouldFailReadLogFile = false;
  bool shouldFailClearLogFile = false;
  bool shouldFailInitialize = false;
  bool shouldFailStartUpload = false;
  bool shouldFailStartDownload = false;
  bool shouldFailCancelOperation = false;
  bool shouldFailStartStream = false;
  bool shouldFailCancelStream = false;
  bool shouldFailRepair = false;
  bool shouldFailGetSettings = false;
  bool shouldFailUpdateSettings = false;
  bool shouldFailGetKeepAliveDiagnostics = false;
  bool shouldFailEnableRelayFileLogging = false;
  bool shouldFailReadRelayLogFile = false;
  bool shouldFailClearRelayLogFile = false;

  final StreamController<String> _relayResponseController =
      StreamController<String>.broadcast();
  final StreamController<dynamic> _relayStreamResponseController =
      StreamController<dynamic>.broadcast();
  final StreamController<String> _relayRequestChunksController =
      StreamController<String>.broadcast();
  final StreamController<String> _relayStreamCompletionController =
      StreamController<String>.broadcast();
    final StreamController<RelayOperationEvent> _eventsController =
      StreamController<RelayOperationEvent>.broadcast();

  @override
  Stream<String> get relayResponseStream => _relayResponseController.stream;

  @override
  Stream<dynamic> get relayStreamResponseStream =>
      _relayStreamResponseController.stream;

  @override
  Stream<String> get relayRequestChunksStream =>
      _relayRequestChunksController.stream;

  @override
  Stream<String> get relayStreamCompletionStream =>
      _relayStreamCompletionController.stream;

  @override
  Stream<RelayOperationEvent> get events => _eventsController.stream;

  void simulateRelayResponse(String message) => _relayResponseController.add(message);

  void simulateRelayStreamResponse(dynamic payload) =>
      _relayStreamResponseController.add(payload);

  void simulateRelayRequestChunks(String streamId) =>
      _relayRequestChunksController.add(streamId);

  void simulateRelayStreamCompletion(String progress) =>
      _relayStreamCompletionController.add(progress);

  void simulateEvent(RelayOperationEvent event) => _eventsController.add(event);

  @override
  Future<void> initialize() async {
    initializeCallCount++;
    if (shouldFailInitialize) {
      throw Exception('initialize failed');
    }
  }

  @override
  Future<String> startUpload(RelayFileUploadRequest request) async {
    startUploadCallCount++;
    lastStartUploadRequest = request;
    if (shouldFailStartUpload) {
      throw Exception('startUpload failed');
    }
    return startUploadResult;
  }

  @override
  Future<String> startDownload(RelayFileDownloadRequest request) async {
    startDownloadCallCount++;
    lastStartDownloadRequest = request;
    if (shouldFailStartDownload) {
      throw Exception('startDownload failed');
    }
    return startDownloadResult;
  }

  @override
  Future<bool> cancelOperation(String operationId) async {
    cancelOperationCallCount++;
    lastCancelOperationId = operationId;
    if (shouldFailCancelOperation) {
      throw Exception('cancelOperation failed');
    }
    return cancelOperationResult;
  }

  @override
  Future<String> startStream(RelayRequest request) async {
    startStreamCallCount++;
    lastStartStreamRequest = request;
    if (shouldFailStartStream) {
      throw Exception('startStream failed');
    }
    return startStreamResult;
  }

  @override
  Future<bool> cancelStream(String streamId) async {
    cancelStreamCallCount++;
    if (shouldFailCancelStream) {
      throw Exception('cancelStream failed');
    }
    return cancelStreamResult;
  }

  @override
  Future<void> repair(String serverUrl, {String? pathnamePrefix}) async {
    repairCallCount++;
    lastRepairServerUrl = serverUrl;
    lastRepairPathnamePrefix = pathnamePrefix;
    if (shouldFailRepair) {
      throw Exception('repair failed');
    }
  }

  @override
  Future<RelayClientSettings> getSettings({
    required String serverUrl,
    String? pathnamePrefix,
  }) async {
    getSettingsCallCount++;
    lastGetSettingsServerUrl = serverUrl;
    lastGetSettingsPathnamePrefix = pathnamePrefix;
    if (shouldFailGetSettings) {
      throw Exception('getSettings failed');
    }
    return getSettingsResult;
  }

  @override
  Future<String> updateSettings(
    String serverUrl,
    RelayClientSettings settings, {
    String? pathnamePrefix,
  }) async {
    updateSettingsCallCount++;
    lastUpdateSettingsServerUrl = serverUrl;
    lastUpdateSettingsPathnamePrefix = pathnamePrefix;
    lastUpdateSettings = settings;
    if (shouldFailUpdateSettings) {
      throw Exception('updateSettings failed');
    }
    return updateSettingsResult;
  }

  @override
  Future<RelayKeepAliveDiagnostics> getKeepAliveDiagnostics(
    String serverUrl,
  ) async {
    getKeepAliveDiagnosticsCallCount++;
    lastKeepAliveServerUrl = serverUrl;
    if (shouldFailGetKeepAliveDiagnostics) {
      throw Exception('getKeepAliveDiagnostics failed');
    }
    return getKeepAliveDiagnosticsResult;
  }

  @override
  Future<void> enableRelayFileLogging(bool enabled) async {
    enableRelayFileLoggingCallCount++;
    if (shouldFailEnableRelayFileLogging) {
      throw Exception('enableRelayFileLogging failed');
    }
  }

  @override
  Future<String> readRelayLogFile() async {
    readRelayLogFileCallCount++;
    if (shouldFailReadRelayLogFile) {
      throw Exception('readRelayLogFile failed');
    }
    return readLogFileResult;
  }

  @override
  Future<void> clearRelayLogFile() async {
    clearRelayLogFileCallCount++;
    if (shouldFailClearRelayLogFile) {
      throw Exception('clearRelayLogFile failed');
    }
  }

  @override
  Future<String?> getPlatformVersion() async {
    getPlatformVersionCallCount++;
    return platformVersion;
  }

  @override
  Future<void> initializeRelay() async {
    initializeRelayCallCount++;
    if (shouldFailInitializeRelay) {
      throw Exception('initializeRelay failed');
    }
  }

  @override
  Future<String> relayUploadFile(dynamic args) async {
    relayUploadFileCallCount++;
    lastRelayUploadFileArgs = args;
    if (shouldFailRelayUploadFile) {
      throw Exception('relayUploadFile failed');
    }
    return relayUploadFileResult;
  }

  @override
  Future<String> relayDownloadFile(dynamic args) async {
    relayDownloadFileCallCount++;
    lastRelayDownloadFileArgs = args;
    if (shouldFailRelayDownloadFile) {
      throw Exception('relayDownloadFile failed');
    }
    return relayDownloadFileResult;
  }

  @override
  Future<String> rePair({required String url, String? pathnamePrefix}) async {
    rePairCallCount++;
    lastRePairUrl = url;
    lastRePairPathnamePrefix = pathnamePrefix;
    if (shouldFailRePair) {
      throw Exception('rePair failed');
    }
    return rePairResult;
  }

  @override
  Future<String> adjustRelaySettings({
    required String url,
    String? pathnamePrefix,
    required int pairPoolSize,
  }) async {
    adjustRelaySettingsCallCount++;
    lastAdjustRelaySettingsUrl = url;
    lastAdjustRelaySettingsPathnamePrefix = pathnamePrefix;
    lastAdjustRelaySettingsPairPoolSize = pairPoolSize;
    if (shouldFailAdjustRelaySettings) {
      throw Exception('adjustRelaySettings failed');
    }
    return adjustRelaySettingsResult;
  }

  @override
  Future<void> sendChunk(dynamic args) async {
    sendChunkCallCount++;
    lastSendChunkArgs = args;
    if (shouldFailSendChunk) {
      throw Exception('sendChunk failed');
    }
  }

  @override
  Future<void> closeStream(dynamic args) async {
    closeStreamCallCount++;
    lastCloseStreamArgs = args;
    if (shouldFailCloseStream) {
      throw Exception('closeStream failed');
    }
  }

  @override
  Future<String> enableFileLogging(bool isEnabled) async {
    enableFileLoggingCallCount++;
    lastEnableFileLoggingIsEnabled = isEnabled;
    if (shouldFailEnableFileLogging) {
      throw Exception('enableFileLogging failed');
    }
    return enableFileLoggingResult;
  }

  @override
  Future<String> readLogFile() async {
    readLogFileCallCount++;
    if (shouldFailReadLogFile) {
      throw Exception('readLogFile failed');
    }
    return readLogFileResult;
  }

  @override
  Future<String> clearLogFile() async {
    clearLogFileCallCount++;
    if (shouldFailClearLogFile) {
      throw Exception('clearLogFile failed');
    }
    return clearLogFileResult;
  }

  Future<void> dispose() async {
    await _relayResponseController.close();
    await _relayStreamResponseController.close();
    await _relayRequestChunksController.close();
    await _relayStreamCompletionController.close();
    await _eventsController.close();
  }
}
