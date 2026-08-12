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

package com.eclypses.mte_relay;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;


import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

import com.eclypses.relay.LogHelper;
import com.eclypses.relay.Relay;
import com.eclypses.relay.RelayClientSettings;
import com.eclypses.relay.RelaySseListener;
import com.eclypses.relay.RelayFileRequestProperties;
import com.eclypses.relay.RelayResponseListener;
import com.eclypses.relay.RelayStreamCallback;
import com.eclypses.relay.RelayStreamCompletionCallback;
import com.eclypses.relay.RelayStreamResponseListener;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;
import java.io.OutputStream;
import java.io.PipedOutputStream;
import java.net.URL;
import okhttp3.Request.Builder;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

public class MteRelayClientPlugin implements FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
  private static final String TAG = "MteRelaySettings";
  private Context context;
  private MethodChannel methodChannel;
  private MethodChannel methodsChannel;
  private EventChannel eventsChannel;
  private EventChannel.EventSink eventSink;
  private Relay relay;
  private final Map<String, OutputStream> outputStreams = new HashMap<>();
  private final Map<String, CountDownLatch> streamCompletionLatches = new ConcurrentHashMap<>();

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
    this.context = flutterPluginBinding.getApplicationContext();
    methodChannel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "mte_relay_client_plugin");
    methodsChannel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "mte_relay/methods");
    eventsChannel = new EventChannel(flutterPluginBinding.getBinaryMessenger(), "mte_relay/events");
    methodChannel.setMethodCallHandler(this);
    methodsChannel.setMethodCallHandler(this);
    eventsChannel.setStreamHandler(this);
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    this.context = null;
    if (methodChannel != null) {
      methodChannel.setMethodCallHandler(null);
      methodChannel = null;
    }
    if (methodsChannel != null) {
      methodsChannel.setMethodCallHandler(null);
      methodsChannel = null;
    }
    if (eventsChannel != null) {
      eventsChannel.setStreamHandler(null);
      eventsChannel = null;
    }
    eventSink = null;
  }

  @Override
  public void onListen(Object arguments, EventChannel.EventSink events) {
    this.eventSink = events;
  }

  @Override
  public void onCancel(Object arguments) {
    this.eventSink = null;
  }

  // RELAY CALLBACKS
  RelayResponseListener relayResponseListener = (success, message) -> relayResponse(success, message, null);

  private void relayResponse(boolean success, String responseStr, String errorMessage) {
    String safeResponse = responseStr != null ? responseStr : "";
    String resultMessage = "Relay Response: " + success + " " + safeResponse + " "
        + (errorMessage != null ? errorMessage : "");

    new Handler(Looper.getMainLooper()).post(() -> {
      if (methodChannel != null) {
        methodChannel.invokeMethod("relayResponseMessage", resultMessage);
      }
    });

    emitEvent(new HashMap<String, Object>() {{
      put("type", success ? "completed" : "failed");
      put("message", resultMessage);
      put("timestamp", java.time.Instant.now().toString());
    }});
  }

  private void relayStreamResponseMethod(
      int statusCode,
      boolean success,
      String responseStr,
      String errorMessage,
      Map<String, List<String>> responseHeaders) {

    Map<String, Object> args = new HashMap<>();
    byte[] responseData = responseStr != null
        ? responseStr.getBytes(StandardCharsets.UTF_8)
        : new byte[0];
    args.put("success", success);
    args.put("data", responseData);
    args.put("headers", responseHeaders);
    args.put("relayError", errorMessage);
    args.put("pluginError", null);
    args.put("statusCode", statusCode);

    new Handler(Looper.getMainLooper()).post(() -> {
      if (methodChannel != null) {
        methodChannel.invokeMethod("relayStreamResponse", args);
      }
    });

    emitEvent(new HashMap<String, Object>() {{
      put("type", success ? "response" : "failed");
      put("statusCode", statusCode);
      put("headers", responseHeaders != null ? responseHeaders : new HashMap<String, List<String>>());
      put("message", errorMessage);
      put("timestamp", java.time.Instant.now().toString());
    }});
  }

  RelayStreamResponseListener listener = this::relayStreamResponseMethod;

  RelayStreamCallback relayStreamCallback = new RelayStreamCallback() {
    @Override
    public void getRequestBodyStream(PipedOutputStream outputStream) {
      String streamID = UUID.randomUUID().toString();
      CountDownLatch completionLatch = new CountDownLatch(1);
      outputStreams.put(streamID, outputStream);
      streamCompletionLatches.put(streamID, completionLatch);

      // Run the invokeMethod call on the main thread
      new Handler(Looper.getMainLooper()).post(() -> {
        if (methodChannel != null) {
          methodChannel.invokeMethod("getFileStream", streamID);
        }
      });

      try {
        boolean completed = completionLatch.await(5, TimeUnit.MINUTES);
        if (!completed) {
          relayStreamResponseMethod(
              -1,
              false,
              null,
              "Timed out waiting for streamed upload chunks from Flutter.",
              null);
        }
      } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
        relayStreamResponseMethod(
            -1,
            false,
            null,
            "Interrupted while waiting for streamed upload chunks: " + e.getMessage(),
            null);
      } finally {
        streamCompletionLatches.remove(streamID);
      }
    }
  };

  RelayStreamCompletionCallback relayStreamCompletionCallback = new RelayStreamCompletionCallback() {
    @Override
    public void onProgressUpdate(int bytesCompleted, int totalBytes) {
      double streamCompletionPercentage = ((double) bytesCompleted / totalBytes);

      new Handler(Looper.getMainLooper()).post(() -> {
        if (methodChannel != null) {
          methodChannel.invokeMethod("streamCompletionPercentage", streamCompletionPercentage);
        }
      });

      emitEvent(new HashMap<String, Object>() {{
        put("type", "uploadProgress");
        put("bytesCompleted", bytesCompleted);
        put("totalBytes", totalBytes);
        put("timestamp", java.time.Instant.now().toString());
      }});
    }
  };

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    switch (call.method) {

      case "getPlatformVersion":
        result.success("Android " + android.os.Build.VERSION.RELEASE);
        break;

      case "initializeRelay":
      case "initialize":
        initializeRelay(result);
        break;

      case "relayUploadFile":
      case "startUpload":
        if (!ensureRelayInitialized(result, "relayUploadFile")) {
          break;
        }
        Map<String, Object> uploadArgs = ensureArgumentsMap(call.arguments);
        if ("startUpload".equals(call.method)) {
          uploadArgs = mapStartUploadArgsToLegacy(uploadArgs);
        }
        relayFileStreamUpload(uploadArgs, result);
        break;

      case "relayDownloadFile":
      case "startDownload":
        if (!ensureRelayInitialized(result, "relayDownloadFile")) {
          break;
        }
        Map<String, Object> downloadArgs = ensureArgumentsMap(call.arguments);
        if ("startDownload".equals(call.method)) {
          downloadArgs = mapStartDownloadArgsToLegacy(downloadArgs);
        }
        relayFileStreamDownload(downloadArgs, result);
        break;

      case "cancelOperation":
        if (!ensureRelayInitialized(result, "cancelOperation")) {
          break;
        }
        cancelOperation(ensureArgumentsMap(call.arguments), result);
        break;

      case "startStream":
        if (!ensureRelayInitialized(result, "startStream")) {
          break;
        }
        startStream(ensureArgumentsMap(call.arguments), result);
        break;

      case "cancelStream":
        if (!ensureRelayInitialized(result, "cancelStream")) {
          break;
        }
        cancelStream(ensureArgumentsMap(call.arguments), result);
        break;

      case "rePair":
      case "repair":
        if (!ensureRelayInitialized(result, "rePair")) {
          break;
        }
        try {
          Map<String, Object> rePairArgs = ensureArgumentsMap(call.arguments);
          if ("repair".equals(call.method)) {
            rePairArgs = mapRepairArgsToLegacy(rePairArgs);
          }
          rePair(rePairArgs, result);
        } catch (IllegalArgumentException e) {
          result.error("INVALID_ARGUMENTS", e.getMessage(), null);
        }
        break;

      case "adjustRelaySettings":
      case "updateSettings":
        if (!ensureRelayInitialized(result, "adjustRelaySettings")) {
          break;
        }
        try {
          Map<String, Object> adjustRelayArgs = ensureArgumentsMap(call.arguments);
          if ("updateSettings".equals(call.method)) {
            adjustRelayArgs = mapUpdateSettingsArgsToLegacy(adjustRelayArgs);
          }
          // Don't dump the whole args map — log specific fields only (§0).
          LogHelper.debug(TAG, () -> "updateSettings request received");
          final Map<String, Object> asyncAdjustRelayArgs = new HashMap<>(adjustRelayArgs);
          new Thread(() -> adjustRelaySettings(asyncAdjustRelayArgs), "relay-adjust-settings").start();
          LogHelper.debug(TAG, () -> "updateSettings acknowledged to Flutter");
          result.success("Relay settings update requested");
        } catch (IllegalArgumentException e) {
          result.error("INVALID_ARGUMENTS", e.getMessage(), null);
        }
        break;

      case "getSettings":
        if (!ensureRelayInitialized(result, "getSettings")) {
          break;
        }
        getSettings(ensureArgumentsMap(call.arguments), result);
        break;

      case "getKeepAliveDiagnostics":
        if (!ensureRelayInitialized(result, "getKeepAliveDiagnostics")) {
          break;
        }
        getKeepAliveDiagnostics(ensureArgumentsMap(call.arguments), result);
        break;

      case "writeToStream":
        try {
          Map<String, Object> writeToStreamArgs = ensureArgumentsMap(call.arguments);
          writeToStream(writeToStreamArgs, result);
        } catch (IllegalArgumentException e) {
          result.error("INVALID_ARGUMENTS", e.getMessage(), null);
        }
        break;

      case "closeStream":
        try {
          Map<String, Object> closeStreamArgs = ensureArgumentsMap(call.arguments);
          closeStream(closeStreamArgs, result);
        } catch (IllegalArgumentException e) {
          result.error("INVALID_ARGUMENTS", e.getMessage(), null);
        }
        break;

      case "enableFileLogging":
        enableFileLogging(call.arguments, result);
        break;

      case "readLogFile":
        readLogFile(result);
        break;

      case "clearLogFile":
        clearLogFile(result);
        break;

      default:
        result.notImplemented();
        break;
    }
  }

  private void emitEvent(Map<String, Object> event) {
    new Handler(Looper.getMainLooper()).post(() -> {
      if (eventSink != null) {
        eventSink.success(event);
      }
    });
  }

  // CALL TO NATIVE METHODS

  @SuppressWarnings("unchecked")
  private void relayFileStreamUpload(Map<String, Object> args, MethodChannel.Result result) {
    String[] headersToEncrypt = new String[0];
    try {
      String fullUrlString = getFullUrlString(args);
      String pathnamePrefix = (String) args.get("pathnamePrefix");
      String methodString = (String) args.get("method");
      Map<String, String> headers = (Map<String, String>) args.get("headers");
      List<String> headersToEncryptList = (List<String>) args.get("headersToEncrypt");
      if (headersToEncryptList != null) {
        headersToEncrypt = headersToEncryptList.toArray(new String[0]);
      }

      if (fullUrlString == null || methodString == null || headers == null) {
        result.error("INVALID_ARGUMENTS", "Invalid arguments", null);
        return;
      }
      if (!methodString.equals("POST")) {
        result.error(
            "INVALID_ARGUMENTS",
            "Only POST requests are supported for streamed file uploads.",
            null);
        return;
      }

      URL url = new URL(fullUrlString);
      String protocol = url.getProtocol();
      String authority = url.getAuthority();
      String route = url.getPath();
      String host = protocol + "://" + authority;

      RelayFileRequestProperties reqProperties = new RelayFileRequestProperties(
          host,
          route,
          pathnamePrefix,
          headers,
          headersToEncrypt,
          relayStreamCallback);

      relay.uploadFile(
          reqProperties,
          listener,
          (i, i1) -> relayStreamCompletionCallback.onProgressUpdate(i, i1));

      result.success("Upload started");

    } catch (Exception e) {
      result.error("", e.getMessage(), null);
    }
  }

  @SuppressWarnings("unchecked")
  private void relayFileStreamDownload(Map<String, Object> args, MethodChannel.Result result) {
    String[] headersToEncrypt = new String[0];
    try {
      String fullUrlString = getFullUrlString(args);
      String pathnamePrefix = (String) args.get("pathnamePrefix");
      String methodString = (String) args.get("method");
      Map<String, String> headers = (Map<String, String>) args.get("headers");
      List<String> headersToEncryptList = (List<String>) args.get("headersToEncrypt");
      if (headersToEncryptList != null) {
        headersToEncrypt = headersToEncryptList.toArray(new String[0]);
      }
      String downloadLocation = (String) args.get("downloadLocation");

      if (fullUrlString == null || methodString == null || headers == null || downloadLocation == null) {
        result.error("INVALID_ARGUMENTS", "Invalid arguments", null);
        return;
      }
      if (downloadLocation.trim().isEmpty()) {
        result.error("INVALID_ARGUMENTS", "'downloadLocation' must not be blank.", null);
        return;
      }
      if (!methodString.equals("GET")) {
        result.error(
            "INVALID_ARGUMENTS",
            "Only GET requests are supported for streamed file downloads.",
            null);
        return;
      }

      URL url = new URL(fullUrlString);
      String protocol = url.getProtocol();
      String authority = url.getAuthority();
      String route = url.getPath();
      String host = protocol + "://" + authority;

      RelayFileRequestProperties reqProperties = new RelayFileRequestProperties(
          host,
          route,
          pathnamePrefix,
          downloadLocation,
          headers,
          headersToEncrypt);

        // Ensure fields are populated even if constructor arg ordering differs by relay build variant.
        reqProperties.pathnamePrefix = pathnamePrefix;
        reqProperties.downloadPath = downloadLocation;

        relay.downloadFile(
          reqProperties,
          pathnamePrefix,
          listener);

      result.success("Download started");

    } catch (Exception e) {
      result.error("", e.getMessage(), null);
    }
  }

  @SuppressWarnings("unchecked")
  void flattenResponseHeaderMap(Map<String, List<String>> headerMap,
                                Map<String, String> flatHeaders) {
    if (headerMap == null) return;
    for (Map.Entry<String, List<String>> entry : headerMap.entrySet()) {
      if (entry.getValue() != null) {
        flatHeaders.put(entry.getKey(), String.join(",", entry.getValue()));
      }
    }
  }

  private String getFullUrlString(Map<String, Object> args) {
    String urlString = (String) args.get("url");
    String route = (String) args.get("route");

    if (!route.startsWith("/")) {
      route = "/" + route;
    }
    String fullUrlString = urlString + route;
    return fullUrlString;
  }

  private void writeToStream(Map<String, Object> args, MethodChannel.Result result) {
    String streamID = (String) args.get("streamID");
    byte[] data = (byte[]) args.get("data");
    OutputStream outputStream = outputStreams.get(streamID);

    if (streamID == null || data == null || outputStream == null) {
      result.error("INVALID_ARGUMENTS", "writeToStream received invalid arguments.", null);
      relayStreamResponseMethod(
          -1,
          false,
          "",
          "writeToStream received invalid arguments.",
          null);
      return;
    }
    if (!writeToOutputStream(outputStream, data)) {
      result.error("STREAM_WRITE_ERROR", "Failed to write chunk to output stream.", null);
      return;
    }

    result.success("Chunk written");
  }

  private void closeStream(Map<String, Object> args, MethodChannel.Result result) {

    String streamID = (String) args.get("streamID");
    if (streamID == null) {
      result.error("INVALID_ARGUMENTS", "closeStream received invalid arguments.", null);
      relayStreamResponseMethod(
          -1,
          false,
          "",
          "closeStream received invalid arguments.",
          null);
      return;
    }

    OutputStream outputStream = outputStreams.remove(streamID);
    if (outputStream != null) {
      try {
        outputStream.close(); // Ensure it is closed
      } catch (IOException e) {
        result.error("STREAM_CLOSE_ERROR", "closeStream Exception: " + e.getMessage(), null);
        relayStreamResponseMethod(
            -1,
            false,
            null,
            "closeStream Exception: " + e.getMessage(),
            null);
        return;
      }
    }

    CountDownLatch completionLatch = streamCompletionLatches.remove(streamID);
    if (completionLatch != null) {
      completionLatch.countDown();
    }

    result.success("Stream closed");
  }

  private void rePair(Map<String, Object> args, MethodChannel.Result result) {
    String urlString = (String) args.get("url");
    String pathnamePrefix = (String) args.get("pathnamePrefix");

    if (urlString == null || urlString.isEmpty()) {
      result.error("INVALID_ARGUMENTS", "'url' is required for rePair.", null);
      return;
    }

    try {
      relay.rePairWithRelayServer(urlString, pathnamePrefix, relayResponseListener);
    } catch (Exception e) {
      result.error("REPAIR_ERROR", e.getMessage(), null);
      return;
    }

    result.success("Re-pair requested");
  }

  private void adjustRelaySettings(Map<String, Object> args) {
    String serverUrl = (String) args.get("url");
    String pathnamePrefix = (String) args.get("pathnamePrefix");
    LogHelper.debug(TAG, () -> "adjustRelaySettings start serverUrl=" + serverUrl
        + " pathnamePrefix=" + pathnamePrefix);

    try {
      if (serverUrl == null || serverUrl.isEmpty()) {
        throw new IllegalArgumentException("'url' is required for adjustRelaySettings.");
      }

      int basePairs = asInt(args.get("pairPoolSize"), 0);
      if (basePairs <= 0) {
        throw new IllegalArgumentException("'pairPoolSize' or settings.basePairs is required.");
      }

      int minPairs = asInt(args.get("minPairs"), Math.max(1, basePairs));
      int maxPairs = asInt(args.get("maxPairs"), Math.max(basePairs, minPairs));
      int keepAlive = asInt(args.get("keepAliveIntervalSeconds"), 300);
      double acquisitionWait = asDouble(args.get("acquisitionWaitTime"), 1.0);

      RelayClientSettings settings = new RelayClientSettings(
          minPairs,
          basePairs,
          maxPairs,
          keepAlive,
          acquisitionWait);

      String responseMessage = relay.adjustRelaySettings(
          serverUrl,
          pathnamePrefix,
          settings,
          relayResponseListener);
      LogHelper.debug(TAG, () -> "adjustRelaySettings completed response=" + responseMessage);
      relayResponse(
          true,
          responseMessage,
          null);
    } catch (Exception e) {
      LogHelper.error(TAG, "adjustRelaySettings failed", e);
      relayResponse(
          false,
          "\nAdjust RelaySettings Failed",
          "Error: " + e.getMessage());
    }
  }

  private void cancelOperation(Map<String, Object> args, MethodChannel.Result result) {
    String operationId = (String) args.get("operationId");
    if (operationId == null || operationId.isEmpty()) {
      result.error("INVALID_ARGUMENTS", "'operationId' is required.", null);
      return;
    }

    try {
      relay.cancelStreamingOperation(operationId);
      result.success(true);
    } catch (Exception e) {
      result.error("CANCEL_OPERATION_ERROR", e.getMessage(), null);
    }
  }

  private void getSettings(Map<String, Object> args, MethodChannel.Result result) {
    String serverUrl = (String) args.get("serverUrl");
    if (serverUrl == null || serverUrl.isEmpty()) {
      serverUrl = (String) args.get("url");
    }
    String pathnamePrefix = (String) args.get("pathnamePrefix");

    if (serverUrl == null || serverUrl.isEmpty()) {
      result.error("INVALID_ARGUMENTS", "'serverUrl' is required for getSettings.", null);
      return;
    }

    try {
      final String resolvedServerUrl = serverUrl;
      LogHelper.debug(TAG, () -> "getSettings request serverUrl=" + resolvedServerUrl
          + " pathnamePrefix=" + pathnamePrefix);
      RelayClientSettings settings = relay.getRelaySettings(serverUrl);
      Map<String, Object> mapped = new HashMap<>();
      mapped.put("minPairs", settings.getMinPairs());
      mapped.put("basePairs", settings.getBasePairs());
      mapped.put("maxPairs", settings.getMaxPairs());
      mapped.put("keepAliveIntervalSeconds", settings.getKeepAliveIntervalSeconds());
      mapped.put("acquisitionWaitTime", settings.getAcquisitionWaitTime());
      LogHelper.debug(TAG, () -> "getSettings returning " + mapped);
      result.success(mapped);
    } catch (Exception e) {
      LogHelper.error(TAG, "getSettings failed", e);
      result.error("GET_SETTINGS_ERROR", e.getMessage(), null);
    }
  }

  private void getKeepAliveDiagnostics(Map<String, Object> args, MethodChannel.Result result) {
    String serverUrl = (String) args.get("serverUrl");
    if (serverUrl == null || serverUrl.isEmpty()) {
      result.error("INVALID_ARGUMENTS", "'serverUrl' is required.", null);
      return;
    }

    try {
      Object value = relay.getClass()
          .getMethod("getKeepAliveDiagnostics", String.class)
          .invoke(relay, serverUrl);
      String diagnostics = value != null ? value.toString() : "";
      result.success(diagnostics);
    } catch (Throwable e) {
      result.error("KEEP_ALIVE_DIAGNOSTICS_ERROR", e.getMessage(), null);
    }
  }

  private void startStream(Map<String, Object> args, MethodChannel.Result result) {
    String serverUrl = (String) args.get("serverUrl");
    String route = (String) args.get("route");
    String pathnamePrefix = (String) args.get("pathnamePrefix");
    if (serverUrl == null || serverUrl.isEmpty() || route == null || route.isEmpty()) {
      result.error("INVALID_ARGUMENTS", "'serverUrl' and 'route' are required.", null);
      return;
    }

    @SuppressWarnings("unchecked")
    Map<String, String> headers = args.get("headers") instanceof Map
        ? (Map<String, String>) args.get("headers")
        : new HashMap<>();

    @SuppressWarnings("unchecked")
    List<String> headersToEncryptList = args.get("headersToEncrypt") instanceof List
        ? (List<String>) args.get("headersToEncrypt")
        : List.of();
    String[] headersToEncrypt = headersToEncryptList.toArray(new String[0]);

    String fullUrl = serverUrl + (route.startsWith("/") ? route : "/" + route);

    // Honor the caller's method + optional body so a streaming request can POST (e.g. an AI
    // prompt). Dart sends the body as raw bytes under the single `body` key.
    String methodString = args.get("method") instanceof String && !((String) args.get("method")).isEmpty()
        ? (String) args.get("method")
        : "GET";
    byte[] bodyBytes = args.get("body") instanceof byte[] ? (byte[]) args.get("body") : null;
    if (bodyBytes != null && bodyBytes.length == 0) {
      bodyBytes = null;
    }

    Builder reqBuilder = new okhttp3.Request.Builder().url(fullUrl);
    if (bodyBytes != null) {
      String contentType = args.get("contentType") instanceof String
          ? (String) args.get("contentType")
          : "application/octet-stream";
      okhttp3.RequestBody requestBody =
          okhttp3.RequestBody.create(bodyBytes, okhttp3.MediaType.parse(contentType));
      reqBuilder.method(methodString, requestBody);
    } else {
      reqBuilder.method(methodString, null);
    }
    for (Map.Entry<String, String> header : headers.entrySet()) {
      reqBuilder.addHeader(header.getKey(), header.getValue());
    }

    String streamId = relay.startEventStream(
        reqBuilder.build(),
        headersToEncrypt,
        pathnamePrefix,
        new RelaySseListener() {
          @Override
          public void onOpened(String streamId, int statusCode, Map<String, List<String>> responseHeaders) {
            emitEvent(new HashMap<String, Object>() {{
              put("type", "sseOpened");
              put("streamId", streamId);
              put("statusCode", statusCode);
              put("headers", responseHeaders != null ? responseHeaders : new HashMap<String, List<String>>());
              put("timestamp", java.time.Instant.now().toString());
            }});
          }

          @Override
          public void onData(String streamId, byte[] data) {
            emitEvent(new HashMap<String, Object>() {{
              put("type", "sseData");
              put("streamId", streamId);
              put("dataBase64", Base64.getEncoder().encodeToString(data));
              put("timestamp", java.time.Instant.now().toString());
            }});
          }

          @Override
          public void onCompleted(String streamId) {
            emitEvent(new HashMap<String, Object>() {{
              put("type", "sseCompleted");
              put("streamId", streamId);
              put("timestamp", java.time.Instant.now().toString());
            }});
          }

          @Override
          public void onCancelled(String streamId) {
            emitEvent(new HashMap<String, Object>() {{
              put("type", "sseCancelled");
              put("streamId", streamId);
              put("timestamp", java.time.Instant.now().toString());
            }});
          }

          @Override
          public void onError(String streamId,
                              int statusCode,
                              String errorMessage,
                              Map<String, List<String>> responseHeaders) {
            emitEvent(new HashMap<String, Object>() {{
              put("type", "sseError");
              put("streamId", streamId);
              put("statusCode", statusCode);
              put("headers", responseHeaders != null ? responseHeaders : new HashMap<String, List<String>>());
              put("message", errorMessage);
              put("timestamp", java.time.Instant.now().toString());
            }});
          }
        });

    result.success(streamId);
  }

  private void cancelStream(Map<String, Object> args, MethodChannel.Result result) {
    String streamId = (String) args.get("streamId");
    if (streamId == null || streamId.isEmpty()) {
      result.error("INVALID_ARGUMENTS", "'streamId' is required.", null);
      return;
    }

    try {
      boolean cancelled = relay.cancelEventStream(streamId);
      result.success(cancelled);
    } catch (Exception e) {
      result.error("CANCEL_SSE_ERROR", e.getMessage(), null);
    }
  }

  @SuppressWarnings("unchecked")
  private void enableFileLogging(Object args, MethodChannel.Result result) {
    Boolean isEnabled;

    if (args instanceof Boolean) {
      isEnabled = (Boolean) args;
    } else if (args instanceof Map) {
      isEnabled = (Boolean) ((Map<String, Object>) args).get("isEnabled");
    } else {
      isEnabled = null;
    }

    if (isEnabled == null) {
      result.error("INVALID_ARGUMENTS", "'isEnabled' boolean is required.", null);
      return;
    }

    try {
      Relay.enableFileLogging(isEnabled);
      String message = "Success! - File logging " + (isEnabled ? "enabled" : "disabled");
      result.success(message);
    } catch (Exception e) {
      result.error("ENABLE_LOGGING_ERROR", e.getMessage(), null);
    }
  }

  private void readLogFile(MethodChannel.Result result) {
    try {
        String logContents = Relay.readLogFile();
        result.success(logContents);
    } catch (Exception e) {
        result.error("READ_LOG_ERROR", e.getMessage(), null);
    }
  }

  private void clearLogFile(MethodChannel.Result result) {
    try {
      Relay.clearLogFile();
      result.success("Log File Cleared");
    } catch (Exception e) {
      result.error("CLEAR_LOG_ERROR", e.getMessage(), null);
    }
  }

  private void initializeRelay(MethodChannel.Result result) {
    if (context == null) {
      result.error("INITIALIZE_RELAY_ERROR", "Plugin context is null.", null);
      return;
    }

    try {
      relay = Relay.getInstance(context);
    } catch (Throwable throwable) {
      result.error("INITIALIZE_RELAY_ERROR", buildThrowableMessage(throwable), null);
      return;
    }

    if (relay == null) {
      result.error("INITIALIZE_RELAY_ERROR", "Relay.getInstance returned null.", null);
      return;
    }

    result.success("Relay Initialized");
  }

  private String buildThrowableMessage(Throwable throwable) {
    if (throwable == null) {
      return "Unknown error";
    }

    Throwable cause = throwable;
    while (cause.getCause() != null) {
      cause = cause.getCause();
    }

    String message = cause.getMessage();
    if (message == null || message.isEmpty()) {
      return cause.toString();
    }
    return message;
  }

  private boolean ensureRelayInitialized(MethodChannel.Result result, String operation) {
    if (relay != null) {
      return true;
    }

    result.error(
        "RELAY_NOT_INITIALIZED",
        "Relay is not initialized. Call initializeRelay successfully before " + operation + ".",
        null);
    return false;
  }

  // UTILITY METHODS

  private boolean writeToOutputStream(OutputStream outputStream, byte[] buffer) {
    int totalBytesWritten = 0;
    try {
      while (totalBytesWritten < buffer.length) {
        int bytesToWrite = buffer.length - totalBytesWritten;
        outputStream.write(buffer, totalBytesWritten, bytesToWrite);
        totalBytesWritten += bytesToWrite;
      }
      outputStream.flush();
      return true;
    } catch (IOException e) {
      relayStreamResponseMethod(
          0,
          false,
          null,
          e.getMessage(),
          null);
      return false;
    }
  }

  private Map<String, Object> mapStartUploadArgsToLegacy(Map<String, Object> args) {
    Map<String, Object> mapped = new HashMap<>(args);
    mapped.put("url", args.get("serverUrl"));
    mapped.put("method", "POST");
    mapped.put("filePath", args.get("localFilePath"));

    Object headersObj = mapped.get("headers");
    if (headersObj instanceof Map) {
      @SuppressWarnings("unchecked")
      Map<String, String> headers = (Map<String, String>) headersObj;
      mapped.put("headers", headers);
    } else {
      mapped.put("headers", new HashMap<String, String>());
    }
    return mapped;
  }

  private Map<String, Object> mapStartDownloadArgsToLegacy(Map<String, Object> args) {
    Map<String, Object> mapped = new HashMap<>(args);
    mapped.put("url", args.get("serverUrl"));
    mapped.put("method", "GET");
    mapped.put("downloadLocation", args.get("destinationPath"));

    Object headersObj = mapped.get("headers");
    if (!(headersObj instanceof Map)) {
      mapped.put("headers", new HashMap<String, String>());
    }
    return mapped;
  }

  private Map<String, Object> mapRepairArgsToLegacy(Map<String, Object> args) {
    Map<String, Object> mapped = new HashMap<>(args);
    mapped.put("url", args.get("serverUrl"));
    return mapped;
  }

  private Map<String, Object> mapUpdateSettingsArgsToLegacy(Map<String, Object> args) {
    Map<String, Object> mapped = new HashMap<>();
    mapped.put("url", args.get("serverUrl"));
    mapped.put("pathnamePrefix", args.get("pathnamePrefix"));

    Object settingsObj = args.get("settings");
    if (settingsObj instanceof Map) {
      @SuppressWarnings("unchecked")
      Map<String, Object> settings = (Map<String, Object>) settingsObj;
      mapped.put("minPairs", settings.get("minPairs"));
      mapped.put("pairPoolSize", settings.get("basePairs"));
      mapped.put("maxPairs", settings.get("maxPairs"));
      mapped.put("keepAliveIntervalSeconds", settings.get("keepAliveIntervalSeconds"));
      mapped.put("acquisitionWaitTime", settings.get("acquisitionWaitTime"));
    } else {
      mapped.put("pairPoolSize", 0);
    }
    return mapped;
  }

  private int asInt(Object value, int fallback) {
    if (value instanceof Number) {
      return ((Number) value).intValue();
    }
    return fallback;
  }

  private double asDouble(Object value, double fallback) {
    if (value instanceof Number) {
      return ((Number) value).doubleValue();
    }
    return fallback;
  }

  private boolean asBoolean(Object value, boolean fallback) {
    if (value instanceof Boolean) {
      return (Boolean) value;
    }
    return fallback;
  }

  private int readIntReflectively(Class<?> cls, Object target, String fieldName, int fallback) {
    try {
      return (int) cls.getField(fieldName).get(target);
    } catch (Throwable ignored) {
      return fallback;
    }
  }

  private double readDoubleReflectively(
      Class<?> cls,
      Object target,
      String fieldName,
      double fallback) {
    try {
      Object value = cls.getField(fieldName).get(target);
      if (value instanceof Number) {
        return ((Number) value).doubleValue();
      }
      return fallback;
    } catch (Throwable ignored) {
      return fallback;
    }
  }

  private boolean readBooleanReflectively(
      Class<?> cls,
      Object target,
      String fieldName,
      boolean fallback) {
    try {
      Object value = cls.getField(fieldName).get(target);
      if (value instanceof Boolean) {
        return (Boolean) value;
      }
      return fallback;
    } catch (Throwable ignored) {
      return fallback;
    }
  }

  @SuppressWarnings("unchecked")
  private Map<String, Object> ensureArgumentsMap(Object arguments) {
    if (arguments instanceof Map) {
      try {
        return (Map<String, Object>) arguments; // Suppressed internally
      } catch (ClassCastException e) {
        throw new IllegalArgumentException("Invalid argument map structure", e);
      }
    } else {
      throw new IllegalArgumentException("Expected arguments of type Map<String, Object>");
    }
  }

  public Context getContext() {
    return context;
  }
}
