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

import Flutter
import UIKit
import Relay

public class MteRelayClientPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, RelayStreamDelegate, RelayStreamResponseDelegate, RelayStreamCompletionDelegate, RelayServerSentEventDelegate {
    
    
    // MARK:  Class Variables
    var outputStreams: [String: OutputStream] = [:]
    private var methodChannel: FlutterMethodChannel?
    private var methodsChannel: FlutterMethodChannel?
    private var eventsChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?
    private static let channelName = "mte_relay_client_plugin"
    private static let methodsChannelName = "mte_relay/methods"
    private static let eventsChannelName = "mte_relay/events"
    private var relay: Relay?
    private var relaySseContextByStreamId: [String: (serverUrl: String, pathnamePrefix: String?)] = [:]
    // Per-stream SSE parser. The relay delivers raw SSE bytes; we parse them here so
    // the plugin emits one parsed `data` value per `sseData` event — the same
    // contract the Android plugin emits.

    // MARK: Register MethodCannel
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = MteRelayClientPlugin()
        let methodChannel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let methodsChannel = FlutterMethodChannel(name: methodsChannelName, binaryMessenger: registrar.messenger())
        let eventsChannel = FlutterEventChannel(name: eventsChannelName, binaryMessenger: registrar.messenger())
        instance.methodChannel = methodChannel
        instance.methodsChannel = methodsChannel
        instance.eventsChannel = eventsChannel
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        registrar.addMethodCallDelegate(instance, channel: methodsChannel)
        eventsChannel.setStreamHandler(instance)
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
    
    // MARK: RelayDelegates
    
    public func relayStreamResponse(from relayServerUrl: String, data: Data?, response: URLResponse?, error: Error?) {
        
        var pluginError: String? = nil
        guard let relayResponse = response as? HTTPURLResponse else {
            pluginError = "Unable to cast response to HTTPURLResponse"
            let args: [String: Any] = [
                "statusCode": -1,
                "success": false,
                "headers": nil as [String:String]?,
                "relayError": error?.localizedDescription,
                "pluginError": pluginError
            ]
            DispatchQueue.main.async {
                self.methodChannel?.invokeMethod("relayStreamResponse", arguments: args)
            }
            return
        }
        let statusCode = relayResponse.statusCode
        let success = (statusCode >= 200 && statusCode < 300)
        var headers: [String: String] = [:]
        for (key, value) in relayResponse.allHeaderFields {
            if let keyString = key as? String, let valueString = value as? String {
                headers[keyString] = valueString
            } else {
                headers[key.description] = "\(value)" // Convert non-string values to string
            }
        }
        
        let args: [String: Any] = [
            "statusCode": statusCode,
            "success": success,
            "data": data,
            "headers": headers,
            "relayError": error?.localizedDescription,
            "pluginError": pluginError
        ]
        DispatchQueue.main.async {
            self.methodChannel?.invokeMethod("relayStreamResponse", arguments: args)
        }
        emitEvent([
            "type": success ? "response" : "failed",
            "statusCode": statusCode,
            "headers": headers,
            "message": error?.localizedDescription as Any,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
    }
    
    // Get requestBodySgtream from Flutter
    public func getRequestBodyStream(outputStream: OutputStream) {
        let streamID = UUID().uuidString
        outputStreams[streamID] = outputStream
        DispatchQueue.main.async {
            self.methodChannel?.invokeMethod("getFileStream", arguments: streamID)
        }
    }
    
    public func relayResponse(success: Bool, responseStr: String, errorMessage: String?) {
        DispatchQueue.main.async {
            self.methodChannel?.invokeMethod("relayResponseMessage", arguments: "Relay Response: \(success) \(responseStr) \(errorMessage ?? "")");
        }
        emitEvent([
            "type": success ? "completed" : "failed",
            "message": "Relay Response: \(success) \(responseStr) \(errorMessage ?? "")",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
    }
    
    public func streamCompletionPercentage(from relayServerUrl: String, bytesCompleted: Double, totalBytes: Double) {
        let streamCompletionPercentage = totalBytes > 0 ? (bytesCompleted / totalBytes) : 0
        DispatchQueue.main.async {
            self.methodChannel?.invokeMethod("streamCompletionPercentage", arguments: streamCompletionPercentage);
        }
        emitEvent([
            "type": "uploadProgress",
            "bytesCompleted": Int(bytesCompleted),
            "totalBytes": Int(totalBytes),
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
    }

    private func emitEvent(_ event: [String: Any]) {
        DispatchQueue.main.async {
            self.eventSink?(event)
        }
    }

    private func relayNotInitializedResult(_ result: @escaping FlutterResult,
                                           operation: String) {
        result(
            FlutterError(
                code: "RELAY_NOT_INITIALIZED",
                message: "Relay is not initialized. Call initializeRelay successfully before \(operation).",
                details: nil
            )
        )
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
            
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
            
        case "initializeRelay", "initialize":
            Task {
                do {
                    let initializedRelay = try await Relay()
                    initializedRelay.relayServerSentEventDelegate = self
                    self.relay = initializedRelay
                    result("Relay Initialized")
                } catch {
                    result(FlutterError(code: "INITIALIZE_RELAY_ERROR", message: error.localizedDescription, details: nil))
                }
            }

        case "relayUploadFile", "startUpload":
            if let args = call.arguments as? [String: Any]{
                guard let relay = relay else {
                    relayNotInitializedResult(result, operation: "relayUploadFile")
                    return
                }
                relay.relayStreamDelegate = self
                relay.relayStreamResponseDelegate = self
                relay.relayStreamCompletionDelegate = self
                let mappedArgs = call.method == "startUpload" ? mapStartUploadArgsToLegacy(args) : args
                relayFileStreamUpload(mappedArgs, relay, result)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            }

        case "relayDownloadFile", "startDownload":
            if let args = call.arguments as? [String: Any] {
                guard let relay = relay else {
                    relayNotInitializedResult(result, operation: "relayDownloadFile")
                    return
                }
                relay.relayStreamResponseDelegate = self
                let mappedArgs = call.method == "startDownload" ? mapStartDownloadArgsToLegacy(args) : args
                relayFileStreamDownload(mappedArgs, relay, result)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            }

        case "cancelOperation":
            if let args = call.arguments as? [String: Any],
               let streamId = args["operationId"] as? String {
                cancelStream(streamId: streamId, result)
            } else {
                result(false)
            }

        case "startStream":
            if let args = call.arguments as? [String: Any] {
                guard let relay = relay else {
                    relayNotInitializedResult(result, operation: "startStream")
                    return
                }
                startStreamRequest(args, relay, result)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            }

        case "cancelStream":
            if let args = call.arguments as? [String: Any],
               let streamId = args["streamId"] as? String {
                cancelStream(streamId: streamId, result)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "'streamId' is required", details: nil))
            }

        case "rePair", "repair":
            if let args = call.arguments as? [String: Any] {
                guard let relay = relay else {
                    relayNotInitializedResult(result, operation: "rePair")
                    return
                }
                let mappedArgs = call.method == "repair" ? mapRepairArgsToLegacy(args) : args
                rePair(mappedArgs, relay, result)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            }

        case "adjustRelaySettings", "updateSettings":
            if let args = call.arguments as? [String: Any] {
                guard let relay = relay else {
                    relayNotInitializedResult(result, operation: "adjustRelaySettings")
                    return
                }
                let mappedArgs = call.method == "updateSettings" ? mapUpdateSettingsArgsToLegacy(args) : args
                adjustRelaySettings(mappedArgs, relay, result)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            }

        case "getSettings":
            if let args = call.arguments as? [String: Any] {
                getSettings(args, result)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            }

        case "getKeepAliveDiagnostics":
            if let args = call.arguments as? [String: Any] {
                getKeepAliveDiagnostics(args, result)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            }

        case "writeToStream":
            if let args = call.arguments as? [String: Any] {
                writeToStream(arguments: args, result)
            }else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            }

        case "closeStream":
            if let args = call.arguments as? [String: Any] {
                closeStream(arguments: args, result)
            }else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            }

        case "enableFileLogging":
            enableFileLogging(call.arguments, result)

        case "readLogFile":
            readLogFile(result)

        case "clearLogFile":
            clearLogFile(result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func mapStartUploadArgsToLegacy(_ args: [String: Any]) -> [String: Any] {
        var mapped = args
        mapped["url"] = args["serverUrl"]
        mapped["method"] = "POST"
        mapped["filePath"] = args["localFilePath"]
        if mapped["headers"] == nil {
            mapped["headers"] = [String: String]()
        }
        if mapped["headersToEncrypt"] == nil {
            mapped["headersToEncrypt"] = [String]()
        }
        return mapped
    }

    private func mapStartDownloadArgsToLegacy(_ args: [String: Any]) -> [String: Any] {
        var mapped = args
        mapped["url"] = args["serverUrl"]
        mapped["method"] = "GET"
        mapped["downloadLocation"] = args["destinationPath"]
        if mapped["headers"] == nil {
            mapped["headers"] = [String: String]()
        }
        if mapped["headersToEncrypt"] == nil {
            mapped["headersToEncrypt"] = [String]()
        }
        return mapped
    }

    private func mapRepairArgsToLegacy(_ args: [String: Any]) -> [String: Any] {
        var mapped = args
        mapped["url"] = args["serverUrl"]
        return mapped
    }

    private func mapUpdateSettingsArgsToLegacy(_ args: [String: Any]) -> [String: Any] {
        var mapped: [String: Any] = [:]
        mapped["url"] = args["serverUrl"]
        mapped["pathnamePrefix"] = args["pathnamePrefix"]
        if let settings = args["settings"] as? [String: Any] {
            mapped["pairPoolSize"] = settings["basePairs"]
            mapped["minPairs"] = settings["minPairs"]
            mapped["maxPairs"] = settings["maxPairs"]
            mapped["keepAliveIntervalSeconds"] = settings["keepAliveIntervalSeconds"]
            mapped["acquisitionWaitTime"] = settings["acquisitionWaitTime"]
        } else {
            mapped["pairPoolSize"] = 0
        }
        return mapped
    }

    private func getSettings(_ args: [String: Any], _ result: @escaping FlutterResult) {
        guard let relay else {
            relayNotInitializedResult(result, operation: "getSettings")
            return
        }
        guard let serverUrl = args["serverUrl"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "'serverUrl' is required", details: nil))
            return
        }
        let pathnamePrefix = args["pathnamePrefix"] as? String

        Task {
            do {
                let settings = try await relay.relaySettings(serverUrl: serverUrl, pathnamePrefix: pathnamePrefix)
                result([
                    "minPairs": settings.minPairs,
                    "basePairs": settings.basePairs,
                    "maxPairs": settings.maxPairs,
                    "keepAliveIntervalSeconds": Int(settings.keepAliveInterval),
                    "acquisitionWaitTime": settings.acquisitionWaitTime
                ])
            } catch {
                result(FlutterError(code: "GET_SETTINGS_ERROR", message: error.localizedDescription, details: nil))
            }
        }
    }

    private func getKeepAliveDiagnostics(_ args: [String: Any], _ result: @escaping FlutterResult) {
        guard let relay else {
            relayNotInitializedResult(result, operation: "getKeepAliveDiagnostics")
            return
        }
        guard let serverUrl = args["serverUrl"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "'serverUrl' is required.", details: nil))
            return
        }
        let pathnamePrefix = args["pathnamePrefix"] as? String

        Task {
            do {
                let settings = try await relay.relaySettings(serverUrl: serverUrl, pathnamePrefix: pathnamePrefix)
                let diagnostics = [
                    "serverUrl=\(serverUrl)",
                    "pathnamePrefix=\(pathnamePrefix ?? "<none>")",
                    "minPairs=\(settings.minPairs)",
                    "basePairs=\(settings.basePairs)",
                    "maxPairs=\(settings.maxPairs)",
                    "keepAliveIntervalSeconds=\(Int(settings.keepAliveInterval))",
                    "acquisitionWaitTime=\(settings.acquisitionWaitTime)"
                ].joined(separator: "\n")
                result(diagnostics)
            } catch {
                result(FlutterError(code: "KEEP_ALIVE_DIAGNOSTICS_ERROR", message: error.localizedDescription, details: nil))
            }
        }
    }

    private func startStreamRequest(_ args: [String: Any],
                                    _ relay: Relay,
                                    _ result: @escaping FlutterResult) {
        let pathnamePrefix = args["pathnamePrefix"] as? String
        guard let serverUrl = args["serverUrl"] as? String,
              let route = args["route"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "'serverUrl' and 'route' are required", details: nil))
            return
        }

        guard var base = URL(string: serverUrl) else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid serverUrl", details: nil))
            return
        }

        let normalizedRoute = route.hasPrefix("/") ? String(route.dropFirst()) : route
        base.appendPathComponent(normalizedRoute)

        var request = URLRequest(url: base)
        // Honor the caller's method (default GET for backward-compatible SSE). The relay frame
        // encodes the logical method; the outer request to the proxy is always POST downstream.
        request.httpMethod = (args["method"] as? String) ?? "GET"
        if let headers = args["headers"] as? [String: String] {
            request.allHTTPHeaderFields = headers
        }

        // Carry an optional request body so a streaming request can POST (e.g. an AI prompt).
        // Dart sends the body as raw bytes under the single `body` key.
        if let body = args["body"] as? FlutterStandardTypedData, !body.data.isEmpty {
            request.httpBody = body.data
        }
        if request.httpBody != nil,
           let contentType = args["contentType"] as? String,
           request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        let headersToEncrypt = args["headersToEncrypt"] as? [String]
        Task {
            do {
                let openResult = try await relay.openServerSentEventStream(
                    with: request,
                    headersToEncrypt: headersToEncrypt,
                    pathnamePrefix: pathnamePrefix,
                    timeout: nil
                )
                let streamId = openResult.streamId.uuidString
                relaySseContextByStreamId[streamId] = (serverUrl, pathnamePrefix)
                result(streamId)
            } catch {
                emitEvent([
                    "type": "sseError",
                    "statusCode": -1,
                    "message": error.localizedDescription,
                    "timestamp": ISO8601DateFormatter().string(from: Date())
                ])
                result(FlutterError(code: "SSE_START_ERROR", message: error.localizedDescription, details: nil))
            }
        }
    }

    private func cancelStream(streamId: String,
                              _ result: @escaping FlutterResult) {
        guard let relay else {
            relayNotInitializedResult(result, operation: "cancelStream")
            return
        }
        guard let uuid = UUID(uuidString: streamId) else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid streamId", details: nil))
            return
        }
        guard let context = relaySseContextByStreamId[streamId] else {
            result(false)
            return
        }

        Task {
            do {
                try await relay.cancelServerSentEventStream(
                    relayServerUrlString: context.serverUrl,
                    streamId: uuid,
                    pathnamePrefix: context.pathnamePrefix
                )
                relaySseContextByStreamId.removeValue(forKey: streamId)
                emitEvent([
                    "type": "sseCancelled",
                    "streamId": streamId,
                    "timestamp": ISO8601DateFormatter().string(from: Date())
                ])
                result(true)
            } catch {
                result(FlutterError(code: "SSE_CANCEL_ERROR", message: error.localizedDescription, details: nil))
            }
        }
    }

    // MARK: RelayServerSentEventDelegate
    public func relayServerSentEventDidReceiveResponse(from relayServerUrl: String,
                                                       streamId: UUID,
                                                       response: URLResponse) {
        let statusCode = (response as? HTTPURLResponse)?.statusCode
        let headers = (response as? HTTPURLResponse)?.allHeaderFields ?? [:]
        emitEvent([
            "type": "sseOpened",
            "streamId": streamId.uuidString,
            "statusCode": statusCode as Any,
            "headers": headers,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
    }

    public func relayServerSentEventDidReceiveData(from relayServerUrl: String,
                                                   streamId: UUID,
                                                   data: Data) {
        // Forward the decrypted bytes untouched. The plugin is a binding, not a framework: it does
        // not parse text/event-stream, because URLSession would not have either. A caller that
        // streams events already owns a parser (MteRelay's RelaySseParser is available opt-in).
        emitSseDataEvent(streamId: streamId.uuidString, data: data)
    }

    public func relayServerSentEventDidComplete(from relayServerUrl: String,
                                                streamId: UUID,
                                                response: URLResponse?) {
        let sid = streamId.uuidString
        relaySseContextByStreamId.removeValue(forKey: sid)
        emitEvent([
            "type": "sseCompleted",
            "streamId": sid,
            "statusCode": (response as? HTTPURLResponse)?.statusCode as Any,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
    }

    private func emitSseDataEvent(streamId: String, data: Data) {
        emitEvent([
            "type": "sseData",
            "streamId": streamId,
            "dataBase64": data.base64EncodedString(),
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
    }
    
    // MARK: Flutter Method Calls to Relay
    fileprivate func relayFileStreamUpload(_ args: [String: Any],
                                           _ relay: Relay,
                                           _ result: @escaping FlutterResult) {
        let pathnamePrefix = args["pathnamePrefix"] as? String
        guard let urlString = args["url"] as? String,
              let url = URL(string: urlString),
              var route = args["route"] as? String,
              let method = args["method"] as? String,
              let headers = args["headers"] as? [String: String],
              let headersToEncrypt = args["headersToEncrypt"] as? [String] else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            return
        }
        if !route.hasPrefix("/") {
            route = "/" + route
        }
        var request = URLRequest(url: url.appendingPathComponent(route))
        request.httpMethod = method
        request.allHTTPHeaderFields = headers

        Task {
            do {
                let (data, response) = try await relay.uploadFileStream(request: request, headersToEncrypt: headersToEncrypt, pathnamePrefix: pathnamePrefix)
                relayStreamResponse(from: urlString, data: data, response: response, error: nil)
                result("Upload completed")
            } catch {
                result(FlutterError(code: "UPLOAD_STREAM_ERROR", message: error.localizedDescription, details: nil))
            }
        }
    }
    
    fileprivate func relayFileStreamDownload(_ args: [String: Any],
                                             _ relay: Relay,
                                             _ result: @escaping FlutterResult) {
        let pathnamePrefix = args["pathnamePrefix"] as? String
        guard let urlString = args["url"] as? String,
              let url = URL(string: urlString),
              var route = args["route"] as? String,
              let method = args["method"] as? String,
              let headers = args["headers"] as? [String: String],
              let headersToEncrypt = args["headersToEncrypt"] as? [String],
              let downloadlocation = args["downloadLocation"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            return
        }
        if !route.hasPrefix("/") {
            route = "/" + route
        }
        var request = URLRequest(url: url.appendingPathComponent(route))
        request.httpMethod = method
        request.allHTTPHeaderFields = headers

        let downloadUrl = URL(fileURLWithPath: downloadlocation)
        do {
            let parentDir = downloadUrl.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        } catch {
            result(FlutterError(code: "DOWNLOAD_STREAM_ERROR", message: "Unable to prepare download directory: \(error.localizedDescription)", details: nil))
            return
        }

        Task {
            do {
                let response = try await relay.downloadFile(with: request, to: downloadUrl, headersToEncrypt: headersToEncrypt, pathnamePrefix: pathnamePrefix)
                relayStreamResponse(from: urlString, data: nil, response: response, error: nil)
                
                // Get file attributes to return size and path
                var fileSize: Int64 = 0
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: downloadUrl.path)
                    if let size = attributes[.size] as? NSNumber {
                        fileSize = size.int64Value
                    }
                } catch {
                    // Continue even if we can't get file attributes
                }
                
                // Build result JSON with download location and file info
                let resultDict: [String: Any] = [
                    "filePath": downloadUrl.path,
                    "downloadLocation": downloadlocation,
                    "fileSize": fileSize,
                    "statusCode": (response as? HTTPURLResponse)?.statusCode ?? 200,
                    "message": "Download completed"
                ]
                
                if let jsonData = try? JSONSerialization.data(withJSONObject: resultDict),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    result(jsonString)
                } else {
                    result("Download completed to \(downloadlocation)")
                }
            } catch {
                result(FlutterError(code: "DOWNLOAD_STREAM_ERROR", message: error.localizedDescription, details: nil))
            }
        }
    }
    
    fileprivate func rePair(_ args: [String: Any],
                            _ relay: Relay,
                            _ result: @escaping FlutterResult) {
        let pathnamePrefix = args["pathnamePrefix"] as? String
        guard let urlString = args["url"] as? String,
              let _ = URL(string: urlString) else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            return
        }

        Task {
            do {
                try await relay.rePairwithRelayServer(relayServerUrlString: urlString, pathnamePrefix: pathnamePrefix)
                let prefixSummary = pathnamePrefix ?? "<none>"
                let message = "Re-pair completed for server=\(urlString), pathnamePrefix=\(prefixSummary)"
                relayResponse(success: true, responseStr: message, errorMessage: nil)
                result(message)
            } catch {
                result(FlutterError(code: "REPAIR_ERROR", message: error.localizedDescription, details: nil))
            }
        }
    }
    
    
    fileprivate func adjustRelaySettings(_ args: [String: Any],
                                         _ relay: Relay,
                                         _ result: @escaping FlutterResult) {
        let pathnamePrefix = args["pathnamePrefix"] as? String
        guard let urlString = args["url"] as? String,
              let _ = URL(string: urlString),
              let newPairPoolSize = args["pairPoolSize"] as? Int else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            return
        }

        let newStreamChunkSize = args["streamChunkSize"] as? Int ?? 1024 * 1024
        let minPairs = args["minPairs"] as? Int ?? RelayHostSettings.defaultMinPairs
        let maxPairs = args["maxPairs"] as? Int ?? max(newPairPoolSize, minPairs)
        let keepAliveInterval =
            (args["keepAliveIntervalSeconds"] as? NSNumber)?.doubleValue ?? RelayHostSettings.defaultKeepAliveInterval
        let acquisitionWaitTime =
            (args["acquisitionWaitTime"] as? NSNumber)?.doubleValue ?? RelayHostSettings.defaultAcquisitionWaitTime

        let settings = RelayHostSettings(
            streamChunkSize: newStreamChunkSize,
            minPairs: minPairs,
            basePairs: newPairPoolSize,
            maxPairs: maxPairs,
            keepAliveInterval: keepAliveInterval,
            acquisitionWaitTime: acquisitionWaitTime
        )

        // Acknowledge immediately to avoid UI stalls if native adjust call blocks.
        let prefixSummary = pathnamePrefix ?? "<none>"
        result("Relay settings update requested: server=\(urlString), pathnamePrefix=\(prefixSummary)")

        Task.detached { [weak self] in
            do {
                try await relay.adjustRelaySettings(
                    serverUrl: urlString,
                    pathnamePrefix: pathnamePrefix,
                    settings: settings
                )
                let message = "Relay settings updated: server=\(urlString), pathnamePrefix=\(prefixSummary), basePairs=\(newPairPoolSize), minPairs=\(minPairs), maxPairs=\(maxPairs)"
                self?.relayResponse(success: true, responseStr: message, errorMessage: nil)
            } catch {
                self?.relayResponse(
                    success: false,
                    responseStr: "\nAdjust RelaySettings Failed",
                    errorMessage: "Error: \(error.localizedDescription)"
                )
            }
        }
    }
    
    func writeToStream(arguments: [String: Any],
                       _ result: @escaping FlutterResult) {
        guard
            let streamID = arguments["streamID"] as? String,
            let data = arguments["data"] as? FlutterStandardTypedData,
            let outputStream = outputStreams[streamID]
        else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "writeToStream received invalid arguments.", details: nil))
            return
        }

        let bytes = [UInt8](data.data)
        writeToOutputStream(outputStream: outputStream, buffer: Data(bytes), result)
    }
    
    func closeStream(arguments: [String: Any],
                     _ result: @escaping FlutterResult) {
        guard
            let streamID = arguments["streamID"] as? String
        else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "closeStream received invalid arguments.", details: nil))
            return
        }

        if let stream = outputStreams[streamID] {
            stream.close()
            outputStreams.removeValue(forKey: streamID)
        }

        result("Stream closed")
    }
    
    func writeToOutputStream(outputStream: OutputStream,
                             buffer: Data,
                             _ result: @escaping FlutterResult) {
        var bytesLeft = buffer.count
        var totalBytesWritten = 0
        
        // Wait until the stream has space available and write in chunks
        while bytesLeft > 0 {
            if outputStream.hasSpaceAvailable {
                // Calculate the range of data to write
                let range = totalBytesWritten..<totalBytesWritten + bytesLeft
                let chunk = buffer.subdata(in: range)
                
                // Write data to the output stream
                let bytesWritten = chunk.withUnsafeBytes {
                    outputStream.write($0.bindMemory(to: UInt8.self).baseAddress!, maxLength: bytesLeft)
                }
                
                // Check for errors
                if bytesWritten < 0 {
                    if let streamError = outputStream.streamError {
                        result(FlutterError(code: "STREAM_WRITE_ERROR", message: "Stream error: \(streamError.localizedDescription)", details: nil))
                    } else {
                        result(FlutterError(code: "STREAM_WRITE_ERROR", message: "Unknown stream write error.", details: nil))
                    }
                    return
                }
                
                // Update counters
                totalBytesWritten += bytesWritten
                bytesLeft -= bytesWritten
            } else {
                // Allow other events to process if the stream is not ready
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            }
        }

        result("Chunk written")
    }
    
    fileprivate func enableFileLogging(_ args: Any?,
                                       _ result: @escaping FlutterResult) {
        var isEnabled: Bool?
        if let direct = args as? Bool {
            isEnabled = direct
        } else if let map = args as? [String: Any] {
            isEnabled = map["isEnabled"] as? Bool
        }

        guard let isEnabled else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            return
        }

        Task {
            do {
                try await Relay.enableFileLogging(isEnabled)
                let message = "Success! - File logging \(isEnabled ? "enabled" : "disabled")"
                result(message)
            } catch {
                result(FlutterError(code: "ENABLE_LOGGING_ERROR", message: error.localizedDescription, details: nil))
            }
        }
    }
    
    fileprivate func readLogFile(_ result: @escaping FlutterResult) {
        Task {
            do {
                result(try await Relay.readLogFile())
            } catch {
                result(FlutterError(code: "READ_LOG_ERROR", message: error.localizedDescription, details: nil))
            }
        }
    }
    
    fileprivate func clearLogFile(_ result: @escaping FlutterResult) {
        Task {
            do {
                try await Relay.clearLogFile()
                result("Log File Cleared")
            } catch {
                result(FlutterError(code: "CLEAR_LOG_ERROR", message: error.localizedDescription, details: nil))
            }
        }
    }
    
    func isUtf8Text(_ data: Data) -> Bool {
        if let _ = String(data: data, encoding: .utf8) {
            return true
        }
        return false
    }
}

/// Incremental SSE (`text/event-stream`) parser. Accepts raw stream bytes in
/// arbitrary chunks and returns one string per completed event — the joined
/// value(s) of that event's `data:` field(s). This lets the plugin emit one
/// parsed `data` value per `sseData` event, matching the Android plugin.
///
