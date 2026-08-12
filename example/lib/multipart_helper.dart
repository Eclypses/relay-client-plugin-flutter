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

import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';

class MultipartHelper {
  final String filename; 
  late final String boundary; 

  MultipartHelper(this.filename) {
    boundary = _generateBoundary(); 
  }


  String _generateBoundary() {
    const length = 32; 
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return 'FlutterBoundary-${List.generate(length, (index) => chars[random.nextInt(chars.length)]).join()}';
  }

  @override
  String toString() {
    return "Filename: $filename\nBoundary: $boundary";
  }

  Uint8List getPrefix() {
    var buffer = StringBuffer();
    buffer.write('--$boundary\r\n');
    buffer.write(
        'Content-Disposition: form-data; name="file"; filename="$filename"\r\n');
    buffer.write('Content-Type: application/octet-stream\r\n\r\n');
    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  Uint8List getPostfix() {
    // RFC 7578 framing for a single file part: end part data with CRLF,
    // then append the terminal boundary in getFinalBoundary().
    return Uint8List.fromList(utf8.encode('\r\n'));
  }

  Uint8List getFinalBoundary() {
    var buffer = StringBuffer();
    buffer.write('--$boundary--\r\n');
    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  Stream<List<int>> assembleMultipartWithFile(File file) async* {
    
    // Add prefix
    yield getPrefix();

    // Read file in chunks
    final fileStream = file.openRead();
    await for (final chunk in fileStream) {
      yield chunk;
    }

    // Add postfix
    yield getPostfix();

    // Add final boundary
    yield getFinalBoundary();
  }

  Future<int> calculateContentLength(File file) async {
    var contentLength = 0;

    int prefixLength = getPrefix().length;
    contentLength += prefixLength;

    int fileLength = await file.length();
    contentLength += fileLength;

    int postfixLength = getPostfix().length;
    contentLength += postfixLength;

    int finalBoundaryLength = getFinalBoundary().length;
    contentLength += finalBoundaryLength;

    return contentLength;
  }
}
