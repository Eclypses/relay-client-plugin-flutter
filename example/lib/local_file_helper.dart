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

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class LocalFileManager {

  final List<String> assetFiles = [
    'assets/JimHalpert.jpeg',
    'assets/Jim_Halpert_Resume.pdf',
    'assets/The Gettysburg Address.txt',
    'assets/War and Peace.txt',
    'assets/25X - War and Peace.txt',
  ];

  Future<void> copyAssetsToDocumentsDirectory() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      for (final assetPath in assetFiles) {
        final fileName = assetPath.split('/').last;
        final file = File('${directory.path}/$fileName');

        // Skip files already copied to avoid expensive startup I/O every launch.
        if (await file.exists()) {
          continue;
        }

        final byteData = await rootBundle.load(assetPath);
        await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      }
    } catch (e) {
      throw Exception("Error getting documents path: $e");
    }
  }

  // Get the application's documents directory
  Future<Directory> _getLocalDirectory() async {
    return await getApplicationDocumentsDirectory();
  }

  // Save a file to local storage
  Future<File> saveFile(String fileName, String content) async {
    final directory = await _getLocalDirectory();
    final file = File('${directory.path}/$fileName');
    return file.writeAsString(content);
  }

  // Read a file from local storage
  Future<String> readFile(String fileName) async {
    try {
      final directory = await _getLocalDirectory();
      final file = File('${directory.path}/$fileName');
      return await file.readAsString();
    } catch (e) {
      throw Exception("File not found: $fileName. Error: $e");
    }
  }

  // List all files in the directory
  Future<List<String>> listFiles() async {
    final directory = await _getLocalDirectory();
    final files = directory.listSync();
    return files.map((file) => file.path).toList();
  }
}
