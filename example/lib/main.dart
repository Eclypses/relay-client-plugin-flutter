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

import 'dart:convert';

// IMPORTANT *********************************************************************
// This example application is currently set to access an Eclypses demo api to
// demonstrate the plugin. Upon startup, the application performs a network call
// to the 'echo' route to confirm the API is running.
// *******************************************************************************

import 'dart:io';

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:mte_relay_client_plugin/mte_relay_client_plugin.dart';
import 'package:mte_relay_client_plugin/mte_relay_response_model.dart';
import 'package:path_provider/path_provider.dart';

import 'local_file_helper.dart';
import 'multipart_helper.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // var relayServerUrl = "https://dev-relay-v5-http-relay-demo.eclypses.com"; // dev V5 server
  var relayServerUrl = "https://mrs-v5-jsonplaceholder.eclypses.com"; // V5 server
  // final String relayServerUrl = "http://10.0.0.219:8080";

  String responseMessage = 'Awaiting response...';
  final _mteRelayClientPlugin = MteRelayClientPlugin();
  final _typedRelayClient = MteRelayClient();
  var authToken = "";
  final headersToEncrypt = ['Content-Type'];
  String? _result;
  double _progress = 0.0;
  late MultipartHelper builder;
  late File file;
  String lastUpload = "";
  Color _responseTextColor = Colors.green;
  Timer? _hideResultTimer;
  final displayResultTimeout = 3;
  final bool autoClearResults = false;
  bool relayUrlIsSet = false;
  // String? pathnamePrefix = "plain-text-prefix";
  String? pathnamePrefix;
  bool fileLoggingEnabled = false;

  @override
  void initState() {
    super.initState();

    if (relayServerUrl == "<your-aws-relay-server-url>") {
      _responseTextColor = Colors.red;
      setState(() {
        _result =
            "\n\n\nRelay Server Url variable must be set in code prior to running this Demo project.";
      });
    } else {
      relayUrlIsSet = true;
    }

    // Listen for responses from the plugin
    _mteRelayClientPlugin.relayResponseStream.listen((message) {
      _showResult(true, message);
    });

    _mteRelayClientPlugin.relayStreamResponseStream.listen((args) {
      bool success = args['success'] as bool;
      int statusCode = args['statusCode'] as int;

      Uint8List? data = _toUint8List(args['data']);

      String? relayError = args["relayError"] as String?;
      String? pluginError = args["pluginError"] as String?;

      if (pluginError != null || relayError != null) {
        String errorMessage = "Error: ${pluginError ?? relayError}";
        _showResult(false, errorMessage);
        return;
      }

      if (!success) {
        _showResult(false, "Error: Stream request failed with statusCode=$statusCode");
        return;
      }

      if (data == null || data.isEmpty) {
        _showResult(true, "Stream completed with empty response body.");
        return;
      }

      // Retrieve a sample Header Value
      Map<String, String>? headers = parseHeaders(args);
      final headerName = "Vary";
      String? header = headers?[headerName];
      if (header != null && header.isNotEmpty) {}
      try {
        final dynamic jsonObject = json.decode(utf8.decode(data));
        String formattedJson = JsonEncoder.withIndent(
          '  ',
        ).convert(jsonObject);
        _showResult(true, formattedJson);
      } catch (e) {
        _showResult(false, "Error: Invalid JSON response.\nDetails: $e");
      }
    });

    _mteRelayClientPlugin.relayRequestChunksStream.listen((streamID) {
      unawaited(startSendingChunks(streamID)); // Start sending chunks
    });

    _mteRelayClientPlugin.relayStreamCompletionStream.listen((progressStr) {
      double? progress = double.tryParse(progressStr);
      _updateProgress(progress ?? 0);
    });

    initializeRelay();
  }

  @override
  void dispose() {
    _hideResultTimer?.cancel();
    super.dispose();
  }

  Future<void> initializeRelay() async {
    try {
      final localFileHelper = LocalFileManager();
      await localFileHelper
          .copyAssetsToDocumentsDirectory(); // Now safe to call
    } catch (e) {
      _showResult(false, 'Error initializing local assets: $e');
    }

    try {
      await _mteRelayClientPlugin.initializeRelay();
      _showResult(true, "Relay Initialized");
    } on PlatformException catch (e) {
      final summary = {
        'success': false,
        'operation': 'initializeRelay',
        'code': e.code,
        'message': e.message,
        'details': e.details,
      };
      _showResult(false, JsonEncoder.withIndent('  ').convert(summary));
    }
  }

  // Adapts a buffered RelayResponse back to the loose map shape Result.fromMap expects.
  Map<dynamic, dynamic> _relayResponseToMap(RelayResponse r) => {
        'success': r.success,
        'statusCode': r.statusCode,
        'data': r.bodyUtf8 ?? r.decodeBodyBase64ToUtf8(),
        'error': r.errorMessage,
        'headers': r.headers,
      };

  Future<void> login() async {
    final body = jsonEncode({"email": "jHalpert.com", "password": "P@ssw0rd!"});
    try {
      Map<dynamic, dynamic> response = _relayResponseToMap(
        await _typedRelayClient
            .send(RelayRequest.text(
              serverUrl: relayServerUrl,
              pathnamePrefix: pathnamePrefix,
              route: "/api/login",
              method: 'POST',
              headers: const {'Content-Type': 'application/json'},
              headersToEncrypt: headersToEncrypt,
              body: body,
            ))
            .timeout(const Duration(seconds: 10)),
      );

      // Retrieve sample Header Value
      final headerName = "Date";
      final result = Result.fromMap(response);

      if (!result.isSuccess) {
        final summary = {
          'success': false,
          'url': relayServerUrl,
          'route': '/api/login',
          'statusCode': result.statusCode,
          'error': result.errorMessage ?? 'Login failed.',
          'headers': result.headers,
        };
        _showResult(false, JsonEncoder.withIndent('  ').convert(summary));
        return;
      }

      final responseBytes = _toUint8List(result.data);
      int? statusCode = result.statusCode;

      String? header = result.headers?[headerName];
      if (header != null && header.isNotEmpty) {}

      if (responseBytes == null) {
        final summary = {
          'success': true,
          'url': relayServerUrl,
          'route': '/api/login',
          'statusCode': statusCode,
          'message': 'Login succeeded with empty response body.',
          'headers': result.headers,
        };
        _showResult(true, JsonEncoder.withIndent('  ').convert(summary));
        return;
      }

      // Display Result
      final dynamic jsonObject = json.decode(utf8.decode(responseBytes));
      _showResult(true, JsonEncoder.withIndent('  ').convert(jsonObject));
    } on PlatformException {
      _showResult(false, 'Failed to Login with Relay.');
    } catch (error) {
      _showResult(false, "Error: $error");
    }
  }

  Future<void> kyc() async {
    // String urlWithPath = "$relayServerUrl/api/kyc";

    final boundary = 'Boundary-${DateTime.now().millisecondsSinceEpoch}';
    final body = BytesBuilder();

    final List<Map<String, dynamic>> parameters = [
      {"key": "firstName", "value": "Jim", "type": "text"},
      {"key": "lastName", "value": "Halpert", "type": "text"},
      {"key": "ssn", "value": "111-22-3333", "type": "text"},
      {"key": "file1", "src": getFileToUpload("image"), "type": "file"},
      {"key": "file2", "src": getFileToUpload("resume"), "type": "file"},
    ];

    for (final param in parameters) {
      if (param['disabled'] != null) continue;

      final paramName = param['key'];
      body.add(utf8.encode('--$boundary\r\n'));
      body.add(
        utf8.encode('Content-Disposition: form-data; name="$paramName"'),
      );

      if (param['contentType'] != null) {
        body.add(utf8.encode('\r\nContent-Type: ${param['contentType']}\r\n'));
      }

      final paramType = param['type'];
      if (paramType == 'text') {
        final paramValue = param['value'];
        body.add(utf8.encode('\r\n\r\n$paramValue\r\n'));
      } else if (paramType == 'file') {
        final file = await param["src"];
        String filename = file.path.split(Platform.pathSeparator).last;
        body.add(utf8.encode('; filename="$filename"\r\n'));
        body.add(utf8.encode('Content-Type: application/octet-stream\r\n\r\n'));
        body.add(await file.readAsBytes());
        body.add(utf8.encode('\r\n'));
      }
    }
    body.add(utf8.encode('--$boundary--\r\n'));

    Uint8List bodyBytes = body.toBytes();

    // Send to relay
    try {
      Map<dynamic, dynamic> response = _relayResponseToMap(
        await _typedRelayClient.send(RelayRequest(
          serverUrl: relayServerUrl,
          pathnamePrefix: pathnamePrefix,
          route: "/api/kyc",
          method: 'POST',
          headers: {'Content-Type': 'multipart/form-data; boundary=$boundary'},
          headersToEncrypt: headersToEncrypt,
          body: bodyBytes,
        )),
      );
      final result = Result.fromMap(response);

      if (!result.isSuccess) {
        _showResult(false, result.errorMessage ?? 'KYC failed with empty response body.');
        return;
      }

      final responseBytes = _toUint8List(result.data);
      if (responseBytes == null) {
        _showResult(false, 'KYC succeeded but response body was empty.');
        return;
      }

      _responseTextColor = result.isSuccess ? Colors.green : Colors.red;
      final dynamic jsonObject = json.decode(utf8.decode(responseBytes));
      _showResult(true, JsonEncoder.withIndent('  ').convert(jsonObject));
    } on PlatformException {
      _showResult(false, 'KYC failed with Relay.');
    } catch (error) {
      _showResult(false, "Error: $error");
    }
  }

  Future<void> uploadFileStream(String filesize) async {
    file = await getFileToUpload(filesize);
    String filename = file.path.split(Platform.pathSeparator).last;

    builder = MultipartHelper(filename);

    String contentTypeHeader =
        'multipart/form-data; boundary=${builder.boundary}';
    int contentLength = await builder.calculateContentLength(file);

    final dynamic args = {
      'url': relayServerUrl,
      'pathnamePrefix': pathnamePrefix,
      'route': "/api/files/upload",
      'method': 'POST',
      'headers': {
        'Content-Type': contentTypeHeader,
        'Content-Length': contentLength.toString(),
        'Content-Transfer-Encoding': 'binary',
      },
      // Keep multipart framing headers in clear for upload boundary parsing.
      'headersToEncrypt': const <String>[],
    };

    String result = await _mteRelayClientPlugin.relayUploadFile(args);
    // Stream response callback carries the final payload. Avoid overwriting it.
    if (!result.toLowerCase().contains("completed")) {
      _showResult(true, result);
    }
  }

  Future<void> downloadFileStream() async {
    final urlEncodedFilename = Uri.encodeComponent(lastUpload);
    final downloadLocation = await getDownloadUrl(lastUpload);

    try {
      final arguments = {
        'url': relayServerUrl,
        'pathnamePrefix': pathnamePrefix,
        'route': "/api/files/download/stream/$urlEncodedFilename",
        'method': 'GET',
        'headers': {'Content-Type': 'application/json'},
        'headersToEncrypt': headersToEncrypt,
        'downloadLocation': downloadLocation,
      };
      String result = await _mteRelayClientPlugin.relayDownloadFile(arguments);
      _showResult(true, result);
    } catch (error) {
      _showResult(false, "Error: $error");
    }
  }

  Future<void> rePair() async {
    try {
      String result = await _mteRelayClientPlugin.rePair(
        url: relayServerUrl,
        pathnamePrefix: pathnamePrefix,
      );
      _showResult(true, result);
    } catch (error) {
      _showResult(false, "Error: $error");
    }
  }

  Future<void> adjustRelaySettings(BuildContext dialogContext) async {
    try {
      debugPrint('[settings] requesting current settings');
      final current = await _typedRelayClient.getSettings(
        serverUrl: relayServerUrl,
        pathnamePrefix: pathnamePrefix,
      );
      debugPrint('[settings] current settings ${current.toMap()}');

      if (!dialogContext.mounted) {
        debugPrint('[settings] dialog context unmounted before dialog opened');
        return;
      }

      debugPrint('[settings] opening settings dialog');
      final nextSettings = await _showSettingsEditorDialog(dialogContext, current);
      debugPrint('[settings] dialog returned ${nextSettings?.toMap()}');
      if (nextSettings == null) {
        return;
      }

      debugPrint('[settings] invoking updateSettings ${nextSettings.toMap()}');
      final updateResult = await _typedRelayClient.updateSettings(
        relayServerUrl,
        nextSettings,
        pathnamePrefix: pathnamePrefix,
      );
      debugPrint('[settings] updateSettings acknowledged: $updateResult');

      final summary = {
        'operation': 'updateSettings',
        'serverUrl': relayServerUrl,
        'pathnamePrefix': pathnamePrefix,
        'currentSettings': current.toMap(),
        'appliedSettings': nextSettings.toMap(),
        'nativeResponse': updateResult,
      };
      _showResult(true, const JsonEncoder.withIndent('  ').convert(summary));
    } catch (error) {
      debugPrint('[settings] adjustRelaySettings error: $error');
      _showResult(false, "Error: $error");
    }
  }

  Future<RelayClientSettings?> _showSettingsEditorDialog(
    BuildContext dialogContext,
    RelayClientSettings current,
  ) async {
    final navigator = Navigator.of(dialogContext, rootNavigator: true);
    final minPairsController = TextEditingController(
      text: current.minPairs.toString(),
    );
    final basePairsController = TextEditingController(
      text: current.basePairs.toString(),
    );
    final maxPairsController = TextEditingController(
      text: current.maxPairs.toString(),
    );
    final keepAliveController = TextEditingController(
      text: current.keepAliveIntervalSeconds.toString(),
    );
    final acquisitionWaitController = TextEditingController(
      text: current.acquisitionWaitTime.toString(),
    );

    String? validationError;

    final settings = await showDialog<RelayClientSettings>(
      context: dialogContext,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Relay Settings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: minPairsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Min Pairs',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: basePairsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Base Pairs',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: maxPairsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Max Pairs',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: keepAliveController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Keep Alive (60-600 sec)',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: acquisitionWaitController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Acquisition Wait Time (sec)',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (validationError != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        validationError!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    FocusScope.of(dialogContext).unfocus();
                    navigator.pop();
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    debugPrint('[settings] apply button pressed');
                    FocusScope.of(dialogContext).unfocus();
                    final minPairs =
                        int.tryParse(minPairsController.text.trim()) ??
                        current.minPairs;
                    final basePairs =
                        int.tryParse(basePairsController.text.trim()) ??
                        current.basePairs;
                    final maxPairs =
                        int.tryParse(maxPairsController.text.trim()) ??
                        current.maxPairs;
                    final keepAlive =
                        int.tryParse(keepAliveController.text.trim()) ??
                        current.keepAliveIntervalSeconds;
                    final acquisitionWait =
                        double.tryParse(acquisitionWaitController.text.trim()) ??
                        current.acquisitionWaitTime;

                    if (minPairs < 0 || basePairs < 0 || maxPairs < 0) {
                      setDialogState(() {
                        validationError = 'Pair values must be non-negative.';
                      });
                      return;
                    }

                    var normalizedMinPairs = minPairs;
                    var normalizedBasePairs = basePairs;
                    var normalizedMaxPairs = maxPairs;
                    var normalizedKeepAlive = keepAlive;
                    var normalizedAcquisitionWait = acquisitionWait;

                    if (normalizedMinPairs > normalizedBasePairs) {
                      normalizedMinPairs = normalizedBasePairs;
                    }
                    if (normalizedBasePairs > normalizedMaxPairs) {
                      normalizedMaxPairs = normalizedBasePairs;
                    }

                    if (normalizedKeepAlive < 60) {
                      normalizedKeepAlive = 60;
                    } else if (normalizedKeepAlive > 600) {
                      normalizedKeepAlive = 600;
                    }

                    if (normalizedAcquisitionWait < 0) {
                      normalizedAcquisitionWait = 0;
                    }

                    final candidate = RelayClientSettings(
                      minPairs: normalizedMinPairs,
                      basePairs: normalizedBasePairs,
                      maxPairs: normalizedMaxPairs,
                      keepAliveIntervalSeconds: normalizedKeepAlive,
                      acquisitionWaitTime: normalizedAcquisitionWait,
                    );

                    debugPrint('[settings] popping dialog with ${candidate.toMap()}');
                    navigator.pop(candidate);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );

    minPairsController.dispose();
    basePairsController.dispose();
    maxPairsController.dispose();
    keepAliveController.dispose();
    acquisitionWaitController.dispose();

    return settings;
  }

  void toggleFileLogging() {
    fileLoggingEnabled = !fileLoggingEnabled;
    enableFileLogging(fileLoggingEnabled);
  }

  Future<void> enableFileLogging(bool isEnabled) async {
    try {
      String result = await _mteRelayClientPlugin.enableFileLogging(isEnabled);
      _showResult(true, result);
    } catch (error) {
      _showResult(false, "Error: $error");
    }
  }

  Future<void> readLogFile() async {
    try {
      String result = await _mteRelayClientPlugin.readLogFile();
      _showResult(true, result);
    } catch (error) {
      _showResult(false, "Error: $error");
    }
  }

  Future<void> clearLogFile() async {
    try {
      String result = await _mteRelayClientPlugin.clearLogFile();
      _showResult(true, result);
    } catch (error) {
      _showResult(false, "Error: $error");
    }
  }

  void _showResult(bool isSuccess, String result) {
    _responseTextColor = isSuccess ? Colors.green : Colors.red;
    if (["fail", "unable"].any((word) => result.toLowerCase().contains(word))) {
      _responseTextColor = Colors.red;
    }

    String formattedResult = result;

    // Try to parse the result as JSON and pretty-print if valid
    try {
      final decodedJson = jsonDecode(result);
      formattedResult = const JsonEncoder.withIndent('  ').convert(decodedJson);
    } catch (e) {
      // Not a JSON, keep the original text
    }

    setState(() {
      _result = formattedResult;
    });

    // Cancel any existing timer
    _hideResultTimer?.cancel();

    if (autoClearResults) {
      // Start a new timer to clear the result after displayResultTimeout seconds
      _hideResultTimer = Timer(Duration(seconds: displayResultTimeout), () {
        setState(() {
          _result = null;
          _responseTextColor = Colors.green;
        });
      });
    }
  }

  void _updateProgress(double progress) {
    setState(() {
      _progress = progress;
    });

    // Hide the progress bar when upload completes
    if (progress == 1.0) {
      setState(() {
        _progress = 0.0;
      });
    }
  }

  Future<File> getFileToUpload(String filesize) async {
    const filenames = [
      "The Gettysburg Address.txt", // 1.5kb
      "War and Peace.txt", // 20mb
      "25X - War and Peace.txt", // 100mb
      "JimHalpert.jpeg", // 381kb
      "Jim_Halpert_Resume.pdf", // 4kb
    ];
    var filename = "";
    switch (filesize) {
      case "small":
        filename = filenames[0];
        break;
      case "medium":
        filename = filenames[1];
        break;
      case "large":
        filename = filenames[2];
        break;
      case "image":
        filename = filenames[3];
        break;
      case "resume":
        filename = filenames[4];
        break;
      default:
        filename = filenames[0];
    }

    lastUpload = filename;
    final directory = await getApplicationDocumentsDirectory();
    String dirStr = directory.path;
    return File("$dirStr/$filename");
  }

  Future<void> startSendingChunks(String streamID) async {
    try {
      // Write data to the request stream
      final writeStream = builder.assembleMultipartWithFile(file);
      await for (final chunk in writeStream) {
        final dynamic args = {
          "streamID": streamID,
          "data": Uint8List.fromList(chunk),
        };
        await _mteRelayClientPlugin.sendChunk(args);
      }

      // Notify native layer to close the stream
      final dynamic args = {"streamID": streamID};
      await _mteRelayClientPlugin.closeStream(args);
    } catch (e) {
      _showResult(false, 'Stream write failed: $e');
    }
  }

  Future<String> getDownloadUrl(String filename) async {
    // Retrieve the documents directory
    final Directory docsDir = await getApplicationDocumentsDirectory();

    // Construct the file URL
    final Directory downloadDirectory = Directory('${docsDir.path}/downloads');
    final File storedFile = File('${downloadDirectory.path}/$filename');

    // Create the download directory if it doesn't exist
    if (!await downloadDirectory.exists()) {
      await downloadDirectory.create(recursive: true);
    }

    // Create the file if it doesn't exist and overwrite it empty if it does exist
    if (!await storedFile.exists()) {
      await storedFile.create();
    } else {
      await storedFile.writeAsBytes(
        [],
      ); // Overwrite the file with empty content
    }

    // Return the filePath
    return storedFile.uri.toFilePath();
  }

  bool isUtf8Text(Uint8List bytes) {
    try {
      utf8.decode(bytes, allowMalformed: false);
      return true;
    } catch (e) {
      return false;
    }
  }

  Uint8List? _toUint8List(dynamic raw) {
    if (raw == null) {
      return null;
    }
    if (raw is Uint8List) {
      return raw;
    }
    if (raw is List<int>) {
      return Uint8List.fromList(raw);
    }
    return null;
  }

  Map<String, String>? parseHeaders(dynamic args) {
    Map<String, String>? headers;

    if (args["headers"] != null && args["headers"] is Map) {
      headers = (args["headers"] as Map).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } else {
      headers = null;
    }
    return headers;
  }

  String? _statusText;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.lightGreen,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text("Flutter Plugin Demo"),
          centerTitle: true,
          backgroundColor: Color(0xFFF6531E),
          titleTextStyle: const TextStyle(
            color: Colors.black,
            fontSize: 35,
            fontWeight: FontWeight.bold,
          ),
        ),
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Expandable scrollable area for the result
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child:
                    _result != null && _result!.isNotEmpty
                        ? SingleChildScrollView(
                          child: Text(
                            _result!,
                            textAlign: TextAlign.left,
                            style: TextStyle(
                              fontSize: 16,
                              color: _responseTextColor,
                            ),
                          ),
                        )
                        : Container(),
              ),
            ),

            // Buttons Section
            if (relayUrlIsSet)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Container(
                      color: Color(0xFFF6531E),
                      width: double.infinity,
                      child: const Align(
                        alignment: Alignment.center,
                        child: Text(
                          'Test Calls',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: login,
                          child: const Text(
                            "Login",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF6531E),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: kyc,
                          child: const Text(
                            "KYC",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF6531E),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: () async {
                            await rePair();
                          },
                          child: const Text(
                            "Re-Pair",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF6531E),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Builder(
                          builder: (settingsContext) {
                            return ElevatedButton(
                              onPressed: () async {
                                await adjustRelaySettings(settingsContext);
                              },
                              child: const Text(
                                "Settings",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFF6531E),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),
                    Container(
                      color: Color(0xFFF6531E),
                      width: double.infinity,
                      child: const Align(
                        alignment: Alignment.center,
                        child: Text(
                          'SSE Tools',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Builder(
                      builder: (navContext) {
                        return ElevatedButton(
                          onPressed: () {
                            Navigator.of(navContext).push(
                              MaterialPageRoute<void>(
                                builder: (context) => SseDemoScreen(
                                  client: _typedRelayClient,
                                  relayServerUrl: relayServerUrl,
                                  pathnamePrefix: pathnamePrefix,
                                ),
                              ),
                            );
                          },
                          child: const Text(
                            'Open SSE Demo Screen',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF6531E),
                            ),
                          ),
                        );
                      },
                    ),

                    SizedBox(height: 10),
                    _progress == 0.0
                        ? Container(
                          color: Color(0xFFF6531E),
                          width: double.infinity,
                          child: const Align(
                            alignment: Alignment.center,
                            child: Text(
                              'File Streaming Calls',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        )
                        : (_progress > 0.0 &&
                            _progress < 1.0 &&
                            _statusText != null)
                        ? Text(
                          _statusText!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFFF6531E),
                          ),
                        )
                        : SizedBox.shrink(), // Hide text when upload/download is done
                    // Show progress bar only if progress is greater than 0.0 and less than 1.0
                    _progress > 0.0 && _progress < 1.0
                        ? Column(
                          children: [
                            LinearProgressIndicator(
                              value: _progress,
                              minHeight: 10.0,
                              backgroundColor: Colors.grey[300],
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFFF6531E),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              "${(_progress * 100).toStringAsFixed(1)}%",
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFF6531E),
                              ),
                            ),
                          ],
                        )
                        : SizedBox.shrink(),

                    const SizedBox(height: 16),

                    // Upload Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: () async {
                            setState(() => _statusText = "Uploading ...");
                            await uploadFileStream('small');
                            setState(
                              () => _statusText = null,
                            ); // Reset when done
                          },
                          child: const Text(
                            "1kb",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF6531E),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: () async {
                            setState(() => _statusText = "Uploading ...");
                            await uploadFileStream('medium');
                            setState(() => _statusText = null);
                          },
                          child: const Text(
                            "17mb",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF6531E),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: () async {
                            setState(() => _statusText = "Uploading ...");
                            await uploadFileStream('large');
                            setState(() => _statusText = null);
                          },
                          child: const Text(
                            "100mb",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF6531E),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Download Button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: () async {
                            setState(() => _statusText = "Downloading ...");
                            await downloadFileStream();
                            setState(
                              () => _statusText = null,
                            ); // Reset when done
                          },
                          child: const Text(
                            "Download Last",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF6531E),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      color: Color(0xFFF6531E),
                      width: double.infinity,
                      child: const Align(
                        alignment: Alignment.center,
                        child: Text(
                          'File Logging Calls',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: () async {
                            toggleFileLogging();
                          },
                          child: const Text(
                            "Enable",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF6531E),
                            ),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            readLogFile();
                          },
                          child: const Text(
                            "Read",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF6531E),
                            ),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            clearLogFile();
                          },
                          child: const Text(
                            "Clear",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF6531E),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class SseDemoScreen extends StatefulWidget {
  const SseDemoScreen({
    super.key,
    required this.client,
    required this.relayServerUrl,
    this.pathnamePrefix,
  });

  final MteRelayClient client;
  final String relayServerUrl;
  final String? pathnamePrefix;

  @override
  State<SseDemoScreen> createState() => _SseDemoScreenState();
}

  enum _SseEndpointMode { counter, lorem }

class _SseDemoScreenState extends State<SseDemoScreen> {
    _SseEndpointMode _endpointMode = _SseEndpointMode.counter;
    final TextEditingController _counterCountController =
      TextEditingController(text: '10');
    final TextEditingController _loremCountController =
      TextEditingController(text: '10');
    final TextEditingController _loremVariablesController =
      TextEditingController(text: 'paragraphs=1&sentences=3&minWords=4&maxWords=8');

  final List<_SseLogLine> _globalLog = <_SseLogLine>[];
  final Map<String, _SseStreamViewModel> _streamStateById =
      <String, _SseStreamViewModel>{};
  final Map<String, _SseEventParser> _parserByStreamId =
      <String, _SseEventParser>{};
  final Map<String, Color> _streamColorById = <String, Color>{};
  int _nextStreamColorIndex = 0;

  static const List<Color> _streamPalette = <Color>[
    Color(0xFF4FC3F7),
    Color(0xFFFFB74D),
    Color(0xFF81C784),
    Color(0xFFE57373),
    Color(0xFFBA68C8),
    Color(0xFFAED581),
    Color(0xFF4DB6AC),
    Color(0xFFF06292),
    Color(0xFFFFD54F),
  ];
    final ScrollController _streamCardsScrollController = ScrollController();
    final ScrollController _globalLogScrollController = ScrollController();

  // Each stream is its own per-call subscription now (client.stream), keyed by a
  // local id — no global event bus to demultiplex.
  final Map<String, StreamSubscription<RelayResponseEvent>> _subscriptionById =
      <String, StreamSubscription<RelayResponseEvent>>{};
  int _localStreamCounter = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptionById.values) {
      subscription.cancel();
    }
    _counterCountController.dispose();
    _loremCountController.dispose();
    _loremVariablesController.dispose();
    _streamCardsScrollController.dispose();
    _globalLogScrollController.dispose();
    super.dispose();
  }

  Future<void> _startSingleStream() async {
    final route = _buildSseRoute();
    await _startSseStream(
      route: route,
      label: 'single-${_endpointMode.name}',
    );
  }

  Future<void> _startTripleStreams() async {
    for (final count in <int>[20, 40, 60]) {
      final route = _buildSseRoute(countOverride: count);
      await _startSseStream(
        route: route,
        label: '${_endpointMode.name}-count=$count',
      );
    }
  }

  String _buildSseRoute({int? countOverride}) {
    final count = countOverride ??
        int.tryParse(
          (_endpointMode == _SseEndpointMode.counter
                  ? _counterCountController.text
                  : _loremCountController.text)
              .trim(),
        ) ??
        10;

    if (_endpointMode == _SseEndpointMode.counter) {
      return '/sse/counter?count=$count';
    }

    final rawVars = _loremVariablesController.text.trim();
    final sanitizedVars = rawVars.replaceFirst(RegExp(r'^[?&]+'), '');
    if (sanitizedVars.isEmpty) {
      return '/sse/lorem?count=$count';
    }
    return '/sse/lorem?count=$count&$sanitizedVars';
  }

  Future<void> _startSseStream({required String route, required String label}) async {
    final rawRoute = route.trim();
    if (rawRoute.isEmpty) {
      _appendLog('[SSE] skipped start for $label: empty route');
      return;
    }

    final normalizedRoute = rawRoute.startsWith('/') ? rawRoute : '/$rawRoute';
    final fullUrl = '${widget.relayServerUrl}$normalizedRoute';
    _appendLog('[SSE] starting $label at $fullUrl');

    final streamId = 'stream-${_localStreamCounter++}';
    setState(() {
      _streamStateById[streamId] = _SseStreamViewModel(
        streamId: streamId,
        label: label,
        route: normalizedRoute,
        status: 'starting',
      );
      _parserByStreamId[streamId] = _SseEventParser();
      _colorForStream(streamId);
    });
    _scheduleAutoScroll();

    _subscriptionById[streamId] = widget.client
        .stream(RelayRequest(
      serverUrl: widget.relayServerUrl,
      pathnamePrefix: widget.pathnamePrefix,
      method: 'GET',
      route: normalizedRoute,
      headers: const {'Accept': 'text/event-stream'},
    ))
        .listen(
      (event) {
        switch (event) {
          case RelayResponseStart():
            _applyStreamEvent(streamId, status: 'opened', statusCode: event.statusCode);
          case RelayResponseChunk():
            _applyStreamEvent(streamId,
                status: 'receiving',
                chunk: utf8.decode(event.bytes, allowMalformed: true));
        }
      },
      onError: (Object error) =>
          _applyStreamEvent(streamId, status: 'error', message: error.toString()),
      onDone: () {
        _applyStreamEvent(streamId, status: 'completed', flush: true);
        _subscriptionById.remove(streamId);
      },
    );
    _appendLog('[SSE] started $label streamId=$streamId');
  }

  Future<void> _cancelAllStreams() async {
    final streamIds = _subscriptionById.keys.toList();
    for (final streamId in streamIds) {
      await _subscriptionById.remove(streamId)?.cancel();
      _applyStreamEvent(streamId, status: 'cancelled');
      _appendLog('[SSE] cancelled streamId=$streamId', streamId: streamId);
    }
  }

  void _clearResults() {
    setState(() {
      _globalLog.clear();
      _streamStateById.clear();
      _parserByStreamId.clear();
      _streamColorById.clear();
      _nextStreamColorIndex = 0;
    });
    _scheduleAutoScroll();
  }

  void _applyStreamEvent(
    String streamId, {
    required String status,
    int? statusCode,
    String? chunk,
    String? message,
    bool flush = false,
  }) {
    final hasChunk = chunk != null && chunk.isNotEmpty;
    final parser = _parserByStreamId.putIfAbsent(streamId, _SseEventParser.new);
    final parsedEvents = hasChunk
        ? parser.consume(chunk)
        : (flush ? parser.consume('\n') : const <String>[]);

    if (!mounted) {
      return;
    }

    setState(() {
      final existing = _streamStateById[streamId] ??
          _SseStreamViewModel(
            streamId: streamId,
            label: streamId,
            route: '',
            status: status,
          );

      _streamStateById[streamId] = existing.copyWith(
        status: status,
        statusCode: statusCode,
        chunkCount: existing.chunkCount + (hasChunk ? 1 : 0),
        parsedEventCount: existing.parsedEventCount + parsedEvents.length,
        lastEvent: status,
        lastMessage: message,
        accumulatedText:
            hasChunk ? existing.accumulatedText + chunk : existing.accumulatedText,
      );
    });
    _scheduleAutoScroll();

    _appendLog(
      '[SSE] status=$status streamId=$streamId statusCode=${statusCode?.toString() ?? ''} message=${message ?? ''}',
      streamId: streamId,
    );
    if (hasChunk) {
      _appendLog('[SSE] chunk[$streamId]=$chunk', streamId: streamId);
    }
    for (final parsed in parsedEvents) {
      _appendLog('[SSE] parsed[$streamId]=$parsed', streamId: streamId);
    }
  }

  void _appendLog(String line, {String? streamId}) {
    debugPrint(line);
    if (!mounted) {
      return;
    }
    setState(() {
      final color = streamId == null
          ? Colors.white70
          : _colorForStream(streamId);
      _globalLog.add(_SseLogLine(text: line, color: color));
      if (_globalLog.length > 300) {
        _globalLog.removeRange(0, _globalLog.length - 300);
      }
    });
    _scheduleAutoScroll();
  }

  Color _colorForStream(String streamId) {
    final existing = _streamColorById[streamId];
    if (existing != null) {
      return existing;
    }
    final color = _streamPalette[_nextStreamColorIndex % _streamPalette.length];
    _nextStreamColorIndex++;
    _streamColorById[streamId] = color;
    return color;
  }

  void _scheduleAutoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(_streamCardsScrollController);
      _scrollToBottom(_globalLogScrollController);
    });
  }

  void _scrollToBottom(ScrollController controller) {
    if (!controller.hasClients) {
      return;
    }
    final target = controller.position.maxScrollExtent;
    controller.animateTo(
      target,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final streamCards = _streamStateById.values.toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    return Scaffold(
      appBar: AppBar(
        title: const Text('SSE Demo'),
        backgroundColor: const Color(0xFFF6531E),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('sse/counter'),
                  selected: _endpointMode == _SseEndpointMode.counter,
                  onSelected: (selected) {
                    if (!selected) {
                      return;
                    }
                    setState(() {
                      _endpointMode = _SseEndpointMode.counter;
                    });
                  },
                ),
                ChoiceChip(
                  label: const Text('sse/lorem'),
                  selected: _endpointMode == _SseEndpointMode.lorem,
                  onSelected: (selected) {
                    if (!selected) {
                      return;
                    }
                    setState(() {
                      _endpointMode = _SseEndpointMode.lorem;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _endpointMode == _SseEndpointMode.counter
                  ? _counterCountController
                  : _loremCountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: _endpointMode == _SseEndpointMode.counter
                    ? 'Counter Count'
                    : 'Lorem Count',
                hintText: '10',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_endpointMode == _SseEndpointMode.lorem) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _loremVariablesController,
                decoration: const InputDecoration(
                  labelText: 'Lorem Variables (query string)',
                  hintText: 'paragraphs=1&sentences=3&minWords=4&maxWords=8',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _startSingleStream,
                  child: const Text('Single SSE Stream'),
                ),
                ElevatedButton(
                  onPressed: _startTripleStreams,
                  child: const Text('Start 20 / 40 / 60'),
                ),
                ElevatedButton(
                  onPressed: _cancelAllStreams,
                  child: const Text('Cancel All'),
                ),
                ElevatedButton(
                  onPressed: _clearResults,
                  child: const Text('Clear Results'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFF6531E)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: streamCards.isEmpty
                          ? const Center(child: Text('No active SSE streams yet.'))
                          : ListView.builder(
                            controller: _streamCardsScrollController,
                              itemCount: streamCards.length,
                              itemBuilder: (context, index) {
                                final stream = streamCards[index];
                                final streamColor = _colorForStream(stream.streamId);
                                return Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${stream.label} (${stream.streamId})',
                                          style: TextStyle(
                                            color: streamColor,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text('route: ${stream.route}'),
                                        Text(
                                          'status: ${stream.status} statusCode: ${stream.statusCode?.toString() ?? '-'}',
                                        ),
                                        Text(
                                          'chunks: ${stream.chunkCount} parsed: ${stream.parsedEventCount} last: ${stream.lastEvent}',
                                        ),
                                        if (stream.lastMessage != null &&
                                            stream.lastMessage!.isNotEmpty)
                                          Text('message: ${stream.lastMessage}'),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFF6531E)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: _globalLog.isEmpty
                          ? const Center(child: Text('SSE log output will appear here.'))
                          : ListView.builder(
                            controller: _globalLogScrollController,
                              itemCount: _globalLog.length,
                              itemBuilder: (context, index) {
                                final line = _globalLog[index];
                                return Text(
                                  line.text,
                                  style: TextStyle(fontSize: 12, color: line.color),
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SseStreamViewModel {
  const _SseStreamViewModel({
    required this.streamId,
    required this.label,
    required this.route,
    required this.status,
    this.statusCode,
    this.chunkCount = 0,
    this.parsedEventCount = 0,
    this.lastEvent = '',
    this.lastMessage,
    this.accumulatedText = '',
  });

  final String streamId;
  final String label;
  final String route;
  final String status;
  final int? statusCode;
  final int chunkCount;
  final int parsedEventCount;
  final String lastEvent;
  final String? lastMessage;
  final String accumulatedText;

  _SseStreamViewModel copyWith({
    String? status,
    int? statusCode,
    int? chunkCount,
    int? parsedEventCount,
    String? lastEvent,
    String? lastMessage,
    String? accumulatedText,
  }) {
    return _SseStreamViewModel(
      streamId: streamId,
      label: label,
      route: route,
      status: status ?? this.status,
      statusCode: statusCode ?? this.statusCode,
      chunkCount: chunkCount ?? this.chunkCount,
      parsedEventCount: parsedEventCount ?? this.parsedEventCount,
      lastEvent: lastEvent ?? this.lastEvent,
      lastMessage: lastMessage ?? this.lastMessage,
      accumulatedText: accumulatedText ?? this.accumulatedText,
    );
  }
}

class _SseEventParser {
  String _lineRemainder = '';
  String? _currentEventId;
  final List<String> _currentDataLines = <String>[];

  List<String> consume(String chunk) {
    final parsedEvents = <String>[];
    final joined = _lineRemainder + chunk;
    final lines = joined.split('\n');
    if (joined.endsWith('\n')) {
      _lineRemainder = '';
    } else {
      _lineRemainder = lines.removeLast();
    }

    for (final raw in lines) {
      final line = raw.replaceAll('\r', '');
      if (line.isEmpty) {
        final completed = _finalizeEventIfReady();
        if (completed != null) {
          parsedEvents.add(completed);
        }
        continue;
      }

      if (line.startsWith('id:')) {
        _currentEventId = line.substring(3).trim();
      } else if (line.startsWith('data:')) {
        _currentDataLines.add(line.substring(5).trimLeft());
      }
    }

    return parsedEvents;
  }

  String? _finalizeEventIfReady() {
    if (_currentDataLines.isEmpty) {
      _currentEventId = null;
      return null;
    }
    final payload = _currentDataLines.join('\n');
    final summary = 'id=${_currentEventId ?? '<none>'} data=$payload';
    _currentEventId = null;
    _currentDataLines.clear();
    return summary;
  }
}

class _SseLogLine {
  const _SseLogLine({required this.text, required this.color});

  final String text;
  final Color color;
}
